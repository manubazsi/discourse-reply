import { action } from "@ember/object";
import { service } from "@ember/service";
import { apiInitializer } from "discourse/lib/api";
import DiscourseURL from "discourse/lib/url";

export default apiInitializer("1.8.0", (api) => {
  api.modifyClass("controller:topic", (Superclass) => {
    return class extends Superclass {
      @service quickReply;

      @action
      replyToPost(post) {
        const settings = this.siteSettings;
        const topic = this.model;
        const isPostTarget = !!(
          post &&
          typeof post === "object" &&
          post.post_number
        );

        const useQuickBox =
          settings.quick_reply_box_enabled &&
          topic?.details?.can_create_post &&
          (!isPostTarget || settings.quick_reply_intercept_post_replies);

        if (!useQuickBox) {
          return super.replyToPost(...arguments);
        }

        this.quickReply.focus(isPostTarget ? post : null);

        // The box lives below the last post. If it isn't on screen yet,
        // jump to the end of the topic; the box will focus itself on mount.
        if (!this.quickReply.handler) {
          const url =
            topic.lastPostUrl || `${topic.url}/${topic.highest_post_number}`;
          DiscourseURL.routeTo(url);
        }
      }
    };
  });
});
