# frozen_string_literal: true

# name: discourse-quick-reply-box
# about: XenForo-style quick reply box at the bottom of every topic, replacing the popup composer for replies.
# version: 0.1.0
# authors: manubazsi
# url: https://github.com/your-name/discourse-quick-reply-box
# required_version: 3.3.0

enabled_site_setting :quick_reply_box_enabled

register_asset "stylesheets/common/quick-reply.scss"
