import { tracked } from "@glimmer/tracking";
import Service from "@ember/service";

export default class QuickReplyService extends Service {
  @tracked replyToPost = null;

  handler = null;
  pendingSince = 0;

  register(fn) {
    this.handler = fn;
  }

  unregister(fn) {
    if (this.handler === fn) {
      this.handler = null;
      this.replyToPost = null;
    }
  }

  focus(post = null) {
    this.replyToPost = post;
    if (this.handler) {
      this.handler();
    } else {
      this.pendingSince = Date.now();
    }
  }

  consumePending() {
    const fresh = Date.now() - this.pendingSince < 10000;
    this.pendingSince = 0;
    return fresh;
  }
}
