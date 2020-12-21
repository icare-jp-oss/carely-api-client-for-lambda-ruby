# gem
require "bundler/setup"
require "active_support"
require "active_support/core_ext"

require "./app/graphql/graphql_query"
require "./app/graphql/graphql_mutation"
require "./app/common/common_process"

module App
  module Graphql
    class CarelyClient
      class << self
        include App::Graphql::GraphqlQuery
        include App::Graphql::GraphqlMutation
        include App::Common::CommonProcess

        EMPLOYMENT_STATUS_FIELD = { normal: "通常勤務", limited: "就業制限中", absent: "休職中", retire: "退職", expired: "契約終了" }
        GENDER_FIELD = { male: "男", female: "女" }

        def get_customer(args)
          all_nodes = []
          errors = nil
          first = nil
          after = nil

          catch :break_loop do
            loop do
              results = GraphqlQuery::Client.query(
                GraphqlQuery::CustomerQuery,
                variables: {
                  first: first,
                  after: after,
                  branch_names: [args[:branch_name]],
                  employee_numbers: [args[:employee_number]],
                }
              )
              nodes = results.data.customers.edges.map(&:node)
              all_nodes += nodes
              nodes.each do |node|
                if node&.errors.present?
                  errors = node.errors
                  throw :break_loop
                end
              end
              page_info = results.data.customers.page_info
              break unless page_info.has_next_page

              after = results.data.customers.edges.last.cursor
            end
          end

          return all_nodes, errors
        rescue => e
          carely_notification_error(e)
          raise e
        end

        def change_customer?(spreadsheet_data, carely_customer_data)
          update_column = []

          # 本名
          update_column << :fullname if change_data?(spreadsheet_data[:fullname], carely_customer_data.fullname)
          # 本名(読み)
          update_column << :fullname_ja if change_data?(spreadsheet_data[:fullname_ja], carely_customer_data.fullname_ja)
          # メールアドレス
          update_column << :email if change_data?(spreadsheet_data[:email], carely_customer_data.email)
          # 生年月日
          update_column << :born_on if change_data?(spreadsheet_data[:born_on]&.to_date, carely_customer_data.born_on&.to_date)
          # 性別
          update_column << :gender if change_data?(spreadsheet_data[:gender], carely_customer_data.gender_text)
          # 入社年月日
          update_column << :join_on if change_data?(spreadsheet_data[:join_on]&.to_date, carely_customer_data.join_on&.to_date)
          # 登録グループ名
          update_column << :branch_name if change_data?(spreadsheet_data[:branch_name], carely_customer_data.branch.display_name)
          # 就業ステータス
          update_column << :employment_status if change_data?(spreadsheet_data[:employment_status], carely_customer_data.employment_status_text)
          # 業務形態
          update_column << :working_arrangement if change_data?(spreadsheet_data[:working_arrangement], carely_customer_data.working_arrangement)
          # 部署名
          update_column << :department_name if change_data?(spreadsheet_data[:department_name], carely_customer_data.department&.display_name)
          # 事業場名
          update_column << :workplace_name if change_data?(spreadsheet_data[:workplace_name], carely_customer_data.workplace&.name)
          # 役職
          update_column << :job_title if change_data?(spreadsheet_data[:job_title], carely_customer_data.job_title)
          # 集団分析単位名
          update_column << :group_analysis_name if change_data?(spreadsheet_data[:group_analysis_name], carely_customer_data.group_analysis&.display_name)
          # ストレスチェックの対象
          has_stress_check = if carely_customer_data.has_stress_check == "active"
                               "有効"
                             else
                               "無効"
                             end
          if spreadsheet_data[:has_stress_check].blank?
            spreadsheet_stress_check_data = "無効"
          else
            spreadsheet_stress_check_data = spreadsheet_data[:has_stress_check]
          end
          update_column << :has_stress_check if change_data?(spreadsheet_stress_check_data, has_stress_check)

          { fullname: spreadsheet_data[:fullname], update_column: update_column }
        end

        def change_data?(a, b)
          a ||= ""
          b ||= ""
          a != b
        end

        def upsert_customer(spreadsheet_data, uuid = nil)
          errors = nil
          after_update_customer = nil
          upsert_customer_errors = nil

          results = GraphqlMutation::Client.query(
            GraphqlMutation::CustomerMutation,
            variables: {
              customerInput: {
                uuid: uuid,
                bornOn: spreadsheet_data[:born_on]&.to_date.presence,
                branchName: spreadsheet_data[:branch_name].presence,
                departmentName: spreadsheet_data[:department_name].presence,
                email: spreadsheet_data[:email].presence,
                employeeNumber: spreadsheet_data[:employee_number].presence,
                employmentStatus: EMPLOYMENT_STATUS_FIELD.invert[spreadsheet_data[:employment_status]],
                fullname: spreadsheet_data[:fullname].presence,
                fullnameJa: spreadsheet_data[:fullname_ja].presence,
                gender: GENDER_FIELD.invert[spreadsheet_data[:gender]],
                groupAnalysisName: spreadsheet_data[:group_analysis_name].presence,
                hasStressCheck: spreadsheet_data[:has_stress_check].blank? ? :in_active : :active,
                joinOn: spreadsheet_data[:join_on]&.to_date.presence,
                jobTitle: spreadsheet_data[:job_title].presence,
                workingArrangement: spreadsheet_data[:working_arrangement].presence,
                workplaceName: spreadsheet_data[:workplace_name].presence,
              }
            }
          )
          if results.errors.nil?
            after_update_customer = results.data.upsert_customer
          elsif results.data&.upsert_customer&.errors.present?
            upsert_customer_errors = results.data.upsert_customer.errors
          else
            errors = results.errors
          end
          return { after_update_customer: after_update_customer, errors: errors, upsert_customer_errors: upsert_customer_errors }
        end
      end
    end
  end
end
