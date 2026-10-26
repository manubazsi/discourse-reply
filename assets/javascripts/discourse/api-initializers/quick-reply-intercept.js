import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import { service } from "@ember/service";
import { apiInitializer } from "discourse/lib/api";
import DiscourseURL from "discourse/lib/url";

function buildQuote(post, text, opts = {}) {
  const params = [
    opts.username || post.username,
    `post:${opts.post || post.post_number}`,
    `topic:${opts.topic || post.topic_id}`,
  ];
  if (opts.full) {
    params.push("full:true");
  }
  return `[quote="${params.join(", ")}"]\n${text.trim()}\n[/quote]\n\n`;
}

export default apiInitializer("1.8.0", (api) => {
  api.modifyClass("controller:topic", (Superclass) => {
    return class extends Superclass {
      @service quickReply;

      shouldUseQuickReply() {
        const settings = this.siteSettings;
        const site = getOwner(this).lookup("service:site");
        const disabledOnMobile =
          settings.quick_reply_disable_on_mobile && site?.mobileView;

        return !!(
          settings.quick_reply_box_enabled &&
          !disabledOnMobile &&
          this.model?.details?.can_create_post
        );
      }

      sendToQuickReply(post, quote) {
        const topic = this.model;
        const target = post && Number(post.post_number) > 1 ? post : null;

        this.quickReply.focus(target, quote);

        if (!this.quickReply.handler) {
          const url =
            topic.lastPostUrl || `${topic.url}/${topic.highest_post_number}`;
          DiscourseURL.routeTo(url);
        }
      }

      @action
      replyToPost(post) {
        if (!this.shouldUseQuickReply()) {
          return super.replyToPost(...arguments);
        }

        const quoteState = this.quoteState;
        let target =
          post && typeof post === "object" && post.post_number ? post : null;
        let quote = null;

        if (quoteState?.buffer) {
          const quoted = quoteState.postId
            ? this.model.postStream?.findLoadedPost(quoteState.postId)
            : target;
          if (quoted) {
            quote = buildQuote(quoted, quoteState.buffer, quoteState.opts);
            target = quoted;
          }
          quoteState.clear?.();
        }

        this.sendToQuickReply(target, quote);
      }

      @action
      selectText() {
        if (!this.shouldUseQuickReply()) {
          return super.selectText(...arguments);
        }

        const quoteState = this.quoteState;
        const { postId, buffer, opts } = quoteState;
        const postStream = this.model.postStream;
        const loaded = postStream.findLoadedPost(postId);
        const promise = loaded
          ? Promise.resolve(loaded)
          : postStream.loadPost(postId);

        return promise.then((quotedPost) => {
          this.sendToQuickReply(quotedPost, buildQuote(quotedPost, buffer, opts));
          quoteState.clear?.();
        });
      }
    };
  });
});
