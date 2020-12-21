require "./app/common/slack_api_client"

module App
  module Common
    module CarelyNotification

      def carely_notification_error(message)
        if ENV["execution"].nil?
          raise message
        else
          notification_to_slack(message)
        end
      end

      def carely_notification_information(message)
        if ENV["execution"].nil?
          puts message
        else
          notification_to_slack(message)
        end
      end

      private

      def notification_to_slack(message)
        channel = ENV["notification_slack_channel"]
        App::Common::SlackApiClient.chat_post_message(channel, message)
      end
    end
  end
end
