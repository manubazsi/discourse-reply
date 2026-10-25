import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { extractError } from "discourse/lib/ajax-error";
import { getURLWithCDN } from "discourse/lib/get-url";
import Composer from "discourse/models/composer";
import { i18n } from "discourse-i18n";

export default class QuickReplyBox extends Component {
  static shouldRender(args, context) {
    return (
      !!args.model?.details?.can_create_post &&
      context?.siteSettings?.quick_reply_box_enabled !== false
    );
  }

  @service composer;
  @service currentUser;
  @service quickReply;
  @service site;
  @service siteSettings;

  @tracked text = "";
  @tracked notice = null;
  @tracked noticeIsError = false;
  @tracked submitting = false;

  textarea = null;

  constructor() {
    super(...arguments);
    if (this.hidden) {
      return;
    }
    this.text = this.loadDraft();
    this.quickReply.register(this.focusBox);
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.quickReply.unregister(this.focusBox);
  }

  get hidden() {
    return !!(
      this.siteSettings.quick_reply_disable_on_mobile && this.site.mobileView
    );
  }

  get topic() {
    return this.args.outletArgs.model;
  }

  get isPM() {
    return this.topic.archetype === "private_message";
  }

  get draftKey() {
    return `quick-reply-draft-${this.topic.id}`;
  }

  get avatarSrc() {
    const tpl = this.currentUser?.avatar_template;
    return tpl ? getURLWithCDN(tpl.replace("{size}", "90")) : null;
  }

  get showToolbar() {
    return this.siteSettings.quick_reply_show_toolbar;
  }

  get submitDisabled() {
    return this.submitting || this.text.trim().length === 0;
  }

  loadDraft() {
    try {
      return sessionStorage.getItem(this.draftKey) || "";
    } catch {
      return "";
    }
  }

  saveDraft() {
    try {
      if (this.text) {
        sessionStorage.setItem(this.draftKey, this.text);
      } else {
        sessionStorage.removeItem(this.draftKey);
      }
    } catch {
      return;
    }
  }

  autosize() {
    const el = this.textarea;
    if (!el) {
      return;
    }
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight + 2, 420)}px`;
  }

  @action
  setTextarea(el) {
    this.textarea = el;
    this.autosize();
    if (this.quickReply.consumePending()) {
      this.focusBox();
    }
  }

  @action
  focusBox() {
    const el = this.textarea;
    if (!el) {
      return;
    }
    el.scrollIntoView({ behavior: "smooth", block: "center" });
    el.focus({ preventScroll: true });
  }

  @action
  onInput(event) {
    this.text = event.target.value;
    this.saveDraft();
    this.autosize();
  }

  @action
  onKeydown(event) {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault();
      this.submit();
    } else if (event.key === "Escape") {
      event.target.blur();
    }
  }

  @action
  clearTarget() {
    this.quickReply.replyToPost = null;
  }

  wrap(before, after, placeholder) {
    const el = this.textarea;
    if (!el) {
      return;
    }
    const start = el.selectionStart;
    const end = el.selectionEnd;
    const selected = el.value.slice(start, end) || placeholder;
    const next =
      el.value.slice(0, start) + before + selected + after + el.value.slice(end);
    el.value = next;
    this.text = next;
    this.saveDraft();
    el.focus();
    el.setSelectionRange(
      start + before.length,
      start + before.length + selected.length
    );
    this.autosize();
  }

  @action
  bold() {
    this.wrap("**", "**", i18n("quick_reply.bold"));
  }

  @action
  italic() {
    this.wrap("*", "*", i18n("quick_reply.italic"));
  }

  @action
  quote() {
    this.wrap("> ", "", i18n("quick_reply.quote"));
  }

  @action
  code() {
    this.wrap("`", "`", "code");
  }

  @action
  link() {
    this.wrap("[", "](https://)", i18n("quick_reply.link"));
  }

  resetBox() {
    this.text = "";
    this.saveDraft();
    this.quickReply.replyToPost = null;
    if (this.textarea) {
      this.textarea.value = "";
      this.textarea.style.height = "";
    }
  }

  @action
  async submit() {
    if (this.submitDisabled) {
      return;
    }

    const min = this.isPM
      ? this.siteSettings.min_personal_message_post_length
      : this.siteSettings.min_post_length;
    const raw = this.text.trim();
    if (raw.length < min) {
      this.noticeIsError = true;
      this.notice = i18n("quick_reply.too_short", { min });
      return;
    }

    this.submitting = true;
    this.notice = null;

    const data = { raw, topic_id: this.topic.id };
    const targetNumber = Number(this.quickReply.replyToPost?.post_number);
    if (targetNumber > 1) {
      data.reply_to_post_number = targetNumber;
    }

    try {
      const result = await ajax("/posts.json", { type: "POST", data });

      if (result.action === "enqueued") {
        this.noticeIsError = false;
        this.notice = i18n("quick_reply.queued");
      } else {
        const id = result.id ?? result.post?.id;
        if (id) {
          try {
            await this.topic.postStream?.triggerNewPostInStream(id);
          } catch {
            this.notice = null;
          }
        }
      }
      this.resetBox();
    } catch (e) {
      this.noticeIsError = true;
      this.notice = extractError(e);
    } finally {
      this.submitting = false;
    }
  }

  @action
  openFullComposer() {
    const topic = this.topic;
    this.composer.open({
      action: Composer.REPLY,
      draftKey: topic.draft_key,
      draftSequence: topic.draft_sequence,
      topic,
      post: this.quickReply.replyToPost || undefined,
      reply: this.text,
    });
    this.resetBox();
  }

  <template>
    {{#unless this.hidden}}
      <div class="quick-reply" id="quick-reply-box">
        {{#if this.avatarSrc}}
          <div class="quick-reply__avatar">
            <img src={{this.avatarSrc}} alt="" width="45" height="45" />
          </div>
        {{/if}}

        <div class="quick-reply__main">
          {{#if this.quickReply.replyToPost}}
            <div class="quick-reply__target">
              {{icon "reply"}}
              <span>{{i18n
                  "quick_reply.replying_to"
                  username=this.quickReply.replyToPost.username
                  post_number=this.quickReply.replyToPost.post_number
                }}</span>
              <DButton
                @icon="xmark"
                @action={{this.clearTarget}}
                @title="quick_reply.cancel_target"
                class="btn-flat btn-small quick-reply__target-clear"
              />
            </div>
          {{/if}}

          {{#if this.showToolbar}}
            <div class="quick-reply__toolbar">
              <DButton @icon="bold" @action={{this.bold}} @title="quick_reply.bold" class="btn-flat btn-small" />
              <DButton @icon="italic" @action={{this.italic}} @title="quick_reply.italic" class="btn-flat btn-small" />
              <DButton @icon="quote-right" @action={{this.quote}} @title="quick_reply.quote" class="btn-flat btn-small" />
              <DButton @icon="code" @action={{this.code}} @title="quick_reply.code" class="btn-flat btn-small" />
              <DButton @icon="link" @action={{this.link}} @title="quick_reply.link" class="btn-flat btn-small" />
            </div>
          {{/if}}

          <textarea
            class="quick-reply__input"
            rows="3"
            aria-label={{i18n "quick_reply.aria_label"}}
            placeholder={{i18n "quick_reply.placeholder"}}
            value={{this.text}}
            {{didInsert this.setTextarea}}
            {{on "input" this.onInput}}
            {{on "keydown" this.onKeydown}}
          ></textarea>

          {{#if this.notice}}
            <div
              class="quick-reply__notice
                {{if this.noticeIsError 'is-error' 'is-info'}}"
              role="status"
            >{{this.notice}}</div>
          {{/if}}

          <div class="quick-reply__actions">
            <DButton
              @action={{this.submit}}
              @icon="reply"
              @label="quick_reply.submit"
              @disabled={{this.submitDisabled}}
              @isLoading={{this.submitting}}
              class="btn-primary quick-reply__submit"
            />
            <DButton
              @action={{this.openFullComposer}}
              @icon="up-right-and-down-left-from-center"
              @label="quick_reply.full_composer"
              @title="quick_reply.full_composer_title"
              class="btn-default quick-reply__full"
            />
          </div>
        </div>
      </div>
    {{/unless}}
  </template>
}
