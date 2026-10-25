import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
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

        const site = getOwner(this).lookup("service:site");
        const disabledOnMobile =
          settings.quick_reply_disable_on_mobile && site?.mobileView;

        const useQuickBox =
          settings.quick_reply_box_enabled &&
          !disabledOnMobile &&
          topic?.details?.can_create_post &&
          (!isPostTarget || settings.quick_reply_intercept_post_replies);

        if (!useQuickBox) {
          return super.replyToPost(...arguments);
        }

        const replyTarget =
          isPostTarget && Number(post.post_number) > 1 ? post : null;

        this.quickReply.focus(replyTarget);

        if (!this.quickReply.handler) {
          const url =
            topic.lastPostUrl || `${topic.url}/${topic.highest_post_number}`;
          DiscourseURL.routeTo(url);
        }
      }
    };
  });
});
