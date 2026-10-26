import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { next } from "@ember/runloop";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DEditor from "discourse/components/d-editor";
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

  root = null;

  constructor() {
    super(...arguments);
    if (this.hidden) {
      return;
    }
    this.text = this.loadDraft();
    this.quickReply.register(this.receive);
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.quickReply.unregister(this.receive);
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

  get targetAvatarSrc() {
    const tpl = this.quickReply.replyToPost?.avatar_template;
    return tpl ? getURLWithCDN(tpl.replace("{size}", "40")) : null;
  }

  get placeholderText() {
    return i18n("quick_reply.placeholder");
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

  @action
  setRoot(el) {
    this.root = el;
    const pending = this.quickReply.consumePending();
    if (pending) {
      next(() => this.receive(pending.quote));
    }
  }

  @action
  receive(quote) {
    if (quote) {
      this.appendQuote(quote);
    }
    next(() => this.focusBox());
  }

  appendQuote(quote) {
    const current = this.text;
    let separator = "";
    if (current && !current.endsWith("\n\n")) {
      separator = current.endsWith("\n") ? "\n" : "\n\n";
    }
    this.text = `${current}${separator}${quote}`;
    this.saveDraft();
  }

  focusBox() {
    if (!this.root) {
      return;
    }
    this.root.scrollIntoView({ behavior: "smooth", block: "center" });
    const input = this.root.querySelector(
      "textarea.d-editor-input, .ProseMirror, textarea"
    );
    input?.focus({ preventScroll: true });
  }

  @action
  onChange(value) {
    const updated = typeof value === "string" ? value : value?.target?.value;
    this.text = updated ?? "";
    this.saveDraft();
  }

  @action
  onKeydown(event) {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault();
      this.submit();
    }
  }

  @action
  clearTarget() {
    this.quickReply.replyToPost = null;
  }

  resetBox() {
    this.text = "";
    this.saveDraft();
    this.quickReply.replyToPost = null;
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
      <div class="quick-reply" id="quick-reply-box" {{didInsert this.setRoot}}>
        {{#if this.avatarSrc}}
          <div class="quick-reply__avatar">
            <img src={{this.avatarSrc}} alt="" width="45" height="45" />
          </div>
        {{/if}}

        <div class="quick-reply__main">
          {{#if this.quickReply.replyToPost}}
            <div class="quick-reply__target">
              {{#if this.targetAvatarSrc}}
                <img
                  class="quick-reply__target-avatar"
                  src={{this.targetAvatarSrc}}
                  alt=""
                  width="20"
                  height="20"
                />
              {{else}}
                {{icon "reply"}}
              {{/if}}
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

          <div class="quick-reply__editor" {{on "keydown" this.onKeydown}}>
            <DEditor
              @value={{this.text}}
              @change={{this.onChange}}
              @placeholder="quick_reply.placeholder"
              @placeholderOverride={{this.placeholderText}}
              @topicId={{this.topic.id}}
              @categoryId={{this.topic.category_id}}
              @disabled={{this.submitting}}
            />
          </div>

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
