import { tracked } from "@glimmer/tracking";
import Service from "@ember/service";

export default class QuickReplyService extends Service {
  @tracked replyToPost = null;

  handler = null;
  pendingSince = 0;
  pendingQuote = null;

  register(fn) {
    this.handler = fn;
  }

  unregister(fn) {
    if (this.handler === fn) {
      this.handler = null;
      this.replyToPost = null;
    }
  }

  focus(post = null, quote = null) {
    this.replyToPost = post;
    if (this.handler) {
      this.handler(quote);
    } else {
      this.pendingSince = Date.now();
      this.pendingQuote = quote;
    }
  }

  consumePending() {
    const fresh = Date.now() - this.pendingSince < 10000;
    const quote = this.pendingQuote;
    this.pendingSince = 0;
    this.pendingQuote = null;
    return fresh ? { quote } : null;
  }
}
