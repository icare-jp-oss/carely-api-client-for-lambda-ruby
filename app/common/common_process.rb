# gem
require "bundler/setup"
require "active_support"
require "active_support/core_ext"

require "openssl"
require "base64"

require "./app/google_spreadsheet/api_client"
require "./app/common/carely_notification"

include App::Common::CarelyNotification

module App
  module Common
    module CommonProcess

      def notification_update_column(update_customer_info, spreadsheet_data, carely_data, dry_run)
        end_message = if dry_run == true
                        "に変更があります。"
                      else
                        "を更新しました。"
                      end
        message = "#{update_customer_info[:fullname]}さんのデータ#{end_message} \n ``` 変更対象は「#{update_customer_info[:update_column].map { |name| App::GoogleSpreadsheet::ApiClient::HEADER_WAMEI_DATA_FROM_SYMBOL[name] }.join("、")}」です。\n"
        update_customer_info[:update_column].each do |update_column|
          # 変更前
          message << "(変更前)#{App::GoogleSpreadsheet::ApiClient::HEADER_WAMEI_DATA_FROM_SYMBOL[update_column]}:#{mapping_data(carely_data, update_column)}"
          # 変更後
          if update_column == :has_stress_check && spreadsheet_data[update_column].blank?
            # 「ストレスチェックの対象」列は空文字,nilの場合は「無効」と出力する
            message << "、(変更後)#{App::GoogleSpreadsheet::ApiClient::HEADER_WAMEI_DATA_FROM_SYMBOL[update_column]}:無効\n"
          else
            message << "、(変更後)#{App::GoogleSpreadsheet::ApiClient::HEADER_WAMEI_DATA_FROM_SYMBOL[update_column]}:#{spreadsheet_data[update_column]}\n"
          end
        end
        message << "```"
        carely_notification_information(message)
      end

      def notification_new_customer(spreadsheet_data)
        message = "#{spreadsheet_data[:fullname]}さんが新しい従業員です。:tada: "
        carely_notification_information(message)
      end

      def notification_customer_query_errors(customer_name, messages)
        message = "#{customer_name}さんのデータ取得に失敗しました。:scream: \n ```errors:#{messages}```"
        carely_notification_information(message)
      end

      def notification_upsert_customer_errors(update_or_new, customer_name, messages)
        message = "#{customer_name}さんのデータ#{update_or_new}に失敗しました。:scream: \n ```errors:#{messages}```"
        carely_notification_information(message)
      end

      def mapping_data(carely_data, update_column)
        case update_column
        when :gender
          # 性別
          return carely_data.gender_text
        when :branch_name
          # 登録グループ名
          return carely_data.branch.display_name
        when :employment_status
          # 就業ステータス
          return carely_data.employment_status_text
        when :department_name
          # 部署名
          return carely_data.department&.display_name
        when :workplace_name
          # 事業場名
          return carely_data.workplace&.name
        when :group_analysis_name
          # 集団分析単位名
          return carely_data.group_analysis&.display_name
        when :has_stress_check
          # ストレスチェック対象かどうか
          has_stress_check = if carely_data.has_stress_check == "active"
                               "有効"
                             else
                               "無効"
                             end
          return has_stress_check
        else
          # その他
          return carely_data.send(update_column)
        end
      end

      def retry_header?(event_headers)
        retry_num = event_headers.fetch("X-Slack-Retry-Num", nil)
        retry_reason = event_headers.fetch("X-Slack-Retry-Reason", nil)
        retry_num.present? && (retry_reason == "http_timeout" || retry_reason == "http_error")
      end

      def aes_encrypt(text)
        return text if ENV["execution"].nil?

        salt = ENV["salt"]
        password = ENV["password"]

        enc = OpenSSL::Cipher.new("AES-256-CBC")
        enc.encrypt

        key_iv = OpenSSL::PKCS5.pbkdf2_hmac_sha1(password, salt, 100_000, enc.key_len + enc.iv_len)
        enc.key = key_iv[0, enc.key_len]
        enc.iv = key_iv[enc.key_len, enc.iv_len]
        # 暗号化
        encrypted_text = enc.update(text) + enc.final
        Base64.encode64(encrypted_text).chomp
      end

      def aes_decrypt(text)
        return text if ENV["execution"].nil?

        decode_text = Base64.decode64(text)
        salt = ENV["salt"]
        password = ENV["password"]

        dec = OpenSSL::Cipher.new("AES-256-CBC")
        dec.decrypt

        key_iv = OpenSSL::PKCS5.pbkdf2_hmac_sha1(password, salt, 100_000, dec.key_len + dec.iv_len)
        dec.key = key_iv[0, dec.key_len]
        dec.iv = key_iv[dec.key_len, dec.iv_len]
        # 復号
        decrypted_text = dec.update(decode_text) + dec.final
        decrypted_text
      end

      def custom_trim(string_data)
        return string_data if string_data.nil?

        string_data.gsub(/(\A[[:space:]]+)|([[:space:]]+\z)/, "")
      end
    end
  end
end
