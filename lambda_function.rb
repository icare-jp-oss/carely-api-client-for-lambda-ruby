require "bundler/setup"
require "active_support"
require "active_support/core_ext"

# local file
require "./app/google_spreadsheet/api_client"
require "./app/carely/api_client"
require "./app/graphql/carely_client"
require "./app/common/common_process"
require "./app/common/carely_notification"

include App::Common::CommonProcess
include App::Common::CarelyNotification

def lambda_handler(event:, context:)

  dry_run = true

  # slackのEvent APIの認証用
  if ENV["execution"] == "lambda"
    if event["body"].present? && JSON.parse(event["body"])["challenge"].present?
      return { statusCode: 200, body: JSON.parse(event["body"])["challenge"] }
    end

    # slack APIのretryの場合は処理をしない
    return { statusCode: 200, body: "No need to resend" } if retry_header?(event["headers"])

    json_body = JSON.parse(event["body"])
    # 対象のslackのbot, channel以外は実行せずalert
    channel_id = json_body.dig("event", "channel")
    api_app_id = json_body.dig("api_app_id")

    # 不正なアクセスはcloudwatchで確認
    if channel_id != ENV["channel_id"] || api_app_id != ENV["api_app_id"]
      puts "event_data:#{event.inspect}"
      carely_notification_error("意図しないchannelまたはユーザから実行されました。")
      return { statusCode: 200, body: "OK" }
    end

    # "event": { "blocks": [ { "elements": [ { "type": "rich_text_section",
    #                                          "elements": [ { "type": "user", "user_id":"xxxxxxxxxxx" },
    #                                                        { "type": "text", "text": " 欲しいデータ" }
    #                                                      ]
    #                                      } ]
    #                      } ]
    #          }
    # 上記のようなパラメータが来るので「欲しいデータ」部分を抽出
    text = json_body.dig("event", "blocks", 0, "elements", 0, "elements", 1, "text")
    if text.blank?
      carely_notification_information("`check` or `run` を指定してください。")
      return { statusCode: 200, body: "OK" }
    end

    if custom_trim(text) == "check"
      dry_run = true
      carely_notification_information("スプレッドシートのデータチェックを実行します。:muscle: ")
    elsif custom_trim(text) == "run"
      dry_run = false
      carely_notification_information("スプレッドシートのデータ登録を実行します。:muscle: ")
    else
      carely_notification_information("`check` or `run` 以外は指定できません。")
      return { statusCode: 200, body: "OK" }
    end
  end

  google_api_client = App::GoogleSpreadsheet::ApiClient.new
  spreadsheet_data = google_api_client.read_spreadsheet_data

  spreadsheet_data.each do |spreadsheet_customer_data|
    spreadsheet_customer_data.map {|k, v| spreadsheet_customer_data[k] = custom_trim(v) }

    # Carely APIを使って従業員データを取得
    carely_data, errors = App::Graphql::CarelyClient.get_customer(spreadsheet_customer_data)
    if errors.present?
      # エラー情報を通知
      notification_customer_query_errors(spreadsheet_customer_data[:fullname], errors)
      next
    end

    uuid = nil
    update_customer_info = nil
    if carely_data.present?
      # 更新処理(新規は通らない)
      # データ変更があるかチェック
      update_customer_info = App::Graphql::CarelyClient.change_customer?(spreadsheet_customer_data, carely_data[0])
      next if update_customer_info.empty? || update_customer_info[:update_column].empty?

      uuid = carely_data[0].uuid

      # checkのみの場合はここでreturn
      if dry_run == true
        ### ここでメッセージ通知してnext
        # 更新情報を通知
        notification_update_column(update_customer_info, spreadsheet_customer_data, carely_data[0], dry_run)
        next
      end
    else
      # 新規でcheckのみの場合
      if dry_run == true
        # ここでメッセージ通知してnext
        notification_new_customer(spreadsheet_customer_data)
        next
      end
    end

    # 新規登録/更新 処理
    results = App::Graphql::CarelyClient.upsert_customer(spreadsheet_customer_data, uuid)

    if results[:errors]&.messages.present? && results[:errors]&.details.present?
      if results[:errors]&.messages.has_key?(:data) && results[:errors]&.details.has_key?(:data)
        # エラー情報を通知
        if update_customer_info.present?
          notification_upsert_customer_errors("更新", update_customer_info[:fullname], results[:errors].messages[:data])
        else
          notification_upsert_customer_errors("登録", spreadsheet_customer_data[:fullname], results[:errors].messages[:data])
        end
        next
      end
    end

    if results[:upsert_customer_errors].present?
      error_data = JSON.parse(results[:upsert_customer_errors])
      # エラー情報を通知
      if update_customer_info.present?
        notification_upsert_customer_errors("更新", update_customer_info[:fullname], error_data["full_messages"].join("、"))
      else
        notification_upsert_customer_errors("登録", spreadsheet_customer_data[:fullname], error_data["full_messages"].join("、"))
      end
      next
    end

    # 更新情報を通知
    if update_customer_info.present?
      notification_update_column(update_customer_info, spreadsheet_customer_data, carely_data[0], dry_run)
    else
      carely_notification_information("#{spreadsheet_customer_data[:fullname]}さんのデータを新規登録しました。")
    end
  end
  carely_notification_information("全ての処理が終わりました。")
  return { statusCode: 200, body: "OK" }
end

# localで実行するときは lambda_handler を呼び出す
if ENV["execution"].nil?
  lambda_handler(event: "", context: "")
end
