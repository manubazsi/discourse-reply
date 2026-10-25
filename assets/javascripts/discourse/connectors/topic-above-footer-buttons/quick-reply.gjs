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
import { popupAjaxError } from "discourse/lib/ajax-error";
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
  @tracked uploading = false;
  @tracked dragging = false;

  root = null;
  fileInput = null;

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

  get placeholderText() {
    return i18n("quick_reply.placeholder");
  }

  get submitDisabled() {
    return (
      this.submitting || this.uploading || this.text.trim().length === 0
    );
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
    if (this.quickReply.consumePending()) {
      next(() => this.focusBox());
    }
  }

  @action
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
    const next = typeof value === "string" ? value : value?.target?.value;
    this.text = next ?? "";
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
    const target = this.quickReply.replyToPost;
    const targetNumber = Number(target?.post_number);
    if (targetNumber > 0) {
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
      popupAjaxError(e);
    } finally {
      this.submitting = false;
    }
  }

  @action
  setFileInput(el) {
    this.fileInput = el;
  }

  @action
  openFilePicker() {
    this.fileInput?.click();
  }

  @action
  onFilesChosen(event) {
    const files = Array.from(event.target.files || []);
    event.target.value = "";
    this.uploadFiles(files);
  }

  @action
  onDragOver(event) {
    if (event.dataTransfer?.types?.includes("Files")) {
      event.preventDefault();
      this.dragging = true;
    }
  }

  @action
  onDragLeave(event) {
    if (!this.root?.contains(event.relatedTarget)) {
      this.dragging = false;
    }
  }

  @action
  onDrop(event) {
    const files = Array.from(event.dataTransfer?.files || []);
    this.dragging = false;
    if (files.length) {
      event.preventDefault();
      this.uploadFiles(files);
    }
  }

  @action
  onPaste(event) {
    const files = Array.from(event.clipboardData?.files || []);
    if (files.length) {
      event.preventDefault();
      this.uploadFiles(files);
    }
  }

  extensionOf(file) {
    return (file.name.split(".").pop() || "").toLowerCase();
  }

  isImageFile(file) {
    return /^(png|jpe?g|gif|webp|avif|bmp|ico|heic|heif)$/.test(
      this.extensionOf(file)
    );
  }

  isAllowedFile(file) {
    const lists = [this.siteSettings.authorized_extensions];
    if (this.currentUser?.staff) {
      lists.push(this.siteSettings.authorized_extensions_for_staff);
    }
    const allowed = lists
      .join("|")
      .split("|")
      .map((e) => e.trim().toLowerCase().replace(/^\./, ""))
      .filter(Boolean);
    return allowed.includes("*") || allowed.includes(this.extensionOf(file));
  }

  maxSizeKb(file) {
    return this.isImageFile(file)
      ? this.siteSettings.max_image_size_kb
      : this.siteSettings.max_attachment_size_kb;
  }

  markdownFor(upload, file) {
    const name = (upload.original_filename || file.name)
      .replace(/\.[^.]+$/, "")
      .replace(/[\[\]]/g, "");
    if (this.isImageFile(file)) {
      const w = upload.thumbnail_width || upload.width;
      const h = upload.thumbnail_height || upload.height;
      const dims = w && h ? `|${w}x${h}` : "";
      return `![${name}${dims}](${upload.short_url || upload.url})`;
    }
    const size = upload.human_filesize ? ` (${upload.human_filesize})` : "";
    return `[${upload.original_filename || file.name}|attachment](${
      upload.short_url || upload.url
    })${size}`;
  }

  insertMarkdown(markdown) {
    const ta = this.root?.querySelector("textarea.d-editor-input");
    const current = ta ? ta.value : this.text;
    let next;
    if (ta) {
      const start = ta.selectionStart ?? current.length;
      const end = ta.selectionEnd ?? start;
      const before = current.slice(0, start);
      const lead = before && !before.endsWith("\n") ? "\n" : "";
      next = `${before}${lead}${markdown}\n${current.slice(end)}`;
    } else {
      const lead = current && !current.endsWith("\n") ? "\n" : "";
      next = `${current}${lead}${markdown}\n`;
    }
    this.text = next;
    this.saveDraft();
  }

  async uploadFiles(files) {
    if (!files.length || this.uploading) {
      return;
    }

    this.uploading = true;
    this.notice = null;

    try {
      for (const file of files) {
        if (!this.isAllowedFile(file)) {
          this.noticeIsError = true;
          this.notice = i18n("quick_reply.upload_not_allowed", {
            name: file.name,
          });
          continue;
        }

        const maxKb = this.maxSizeKb(file);
        if (maxKb && file.size / 1024 > maxKb) {
          this.noticeIsError = true;
          this.notice = i18n("quick_reply.upload_too_large", {
            name: file.name,
            max: maxKb,
          });
          continue;
        }

        const form = new FormData();
        form.append("type", "composer");
        form.append("synchronous", "true");
        form.append("file", file, file.name);
        if (this.isPM) {
          form.append("for_private_message", "true");
        }

        try {
          const upload = await ajax("/uploads.json", {
            type: "POST",
            data: form,
            processData: false,
            contentType: false,
          });
          this.insertMarkdown(this.markdownFor(upload, file));
        } catch (e) {
          popupAjaxError(e);
        }
      }
    } finally {
      this.uploading = false;
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
    <div
      class="quick-reply {{if this.dragging 'is-dragging'}}"
      id="quick-reply-box"
      {{didInsert this.setRoot}}
      {{on "dragover" this.onDragOver}}
      {{on "dragleave" this.onDragLeave}}
      {{on "drop" this.onDrop}}
    >
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

        <div
          class="quick-reply__editor"
          {{on "keydown" this.onKeydown}}
          {{on "paste" this.onPaste}}
        >
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

        <input
          type="file"
          multiple
          hidden
          class="quick-reply__file-input"
          {{didInsert this.setFileInput}}
          {{on "change" this.onFilesChosen}}
        />

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
            @action={{this.openFilePicker}}
            @icon="upload"
            @label="quick_reply.upload"
            @title="quick_reply.upload_title"
            @isLoading={{this.uploading}}
            @disabled={{this.submitting}}
            class="btn-default quick-reply__upload"
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
