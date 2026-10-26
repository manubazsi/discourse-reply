import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import { service } from "@ember/service";
import { apiInitializer } from "discourse/lib/api";
import DiscourseURL from "discourse/lib/url";

function buildQuote(post, text, full) {
  const fullFlag = full ? ", full:true" : "";
  return `[quote="${post.username}, post:${post.post_number}, topic:${post.topic_id}${fullFlag}"]\n${text.trim()}\n[/quote]\n\n`;
}

export default apiInitializer("1.8.0", (api) => {
  api.modifyClass("controller:topic", (Superclass) => {
    return class extends Superclass {
      @service quickReply;

      @action
      replyToPost(post) {
        const settings = this.siteSettings;
        const topic = this.model;
        const site = getOwner(this).lookup("service:site");
        const disabledOnMobile =
          settings.quick_reply_disable_on_mobile && site?.mobileView;

        const useQuickBox =
          settings.quick_reply_box_enabled &&
          !disabledOnMobile &&
          topic?.details?.can_create_post;

        if (!useQuickBox) {
          return super.replyToPost(...arguments);
        }

        let target =
          post && typeof post === "object" && Number(post.post_number) > 1
            ? post
            : null;
        let quote = null;

        const quoteState = this.quoteState;
        if (quoteState?.buffer) {
          const quoted = quoteState.postId
            ? topic.postStream?.findLoadedPost(quoteState.postId)
            : post;
          if (quoted) {
            quote = buildQuote(quoted, quoteState.buffer, quoteState.opts?.full);
            target = Number(quoted.post_number) > 1 ? quoted : null;
          }
          quoteState.clear?.();
        }

        this.quickReply.focus(target, quote);

        if (!this.quickReply.handler) {
          const url =
            topic.lastPostUrl || `${topic.url}/${topic.highest_post_number}`;
          DiscourseURL.routeTo(url);
        }
      }
    };
  });
});
