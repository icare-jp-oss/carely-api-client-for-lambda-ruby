# gem
require "bundler/setup"
require "slack-ruby-client"

module App
  module Common
    class SlackApiClient

      def self.chat_post_message(channel, message)
        if ENV["execution"] == "lambda"
          # lambdaではエラーはslackへ通知する
          if @client.nil?
            Slack.configure do |config|
              config.token = ENV["slack_token"]
            end
            @client = Slack::Web::Client.new
          end
          @client.chat_postMessage(channel: channel, text: message)
        end
      end
    end
  end
end
