begin
  require 'pygments.rb'
rescue LoadError
  # Doesn't have pygments.rb installed
end

require "rack/utils"

module Peek
  module ActiveRecord
    module ControllerHelpers
      extend ActiveSupport::Concern

      included do
        around_action :inject_peek_activerecord, :if => [:peek_enabled?, :peek_activerecord_enabled?]
      end

      protected

      def pygments_enabled?
        defined?(Pygments)
      end

      def pygmentized_sql(sql)
        if pygments_enabled?
          Pygments.highlight(sql, :lexer => 'sql')
        else
          "#{Rack::Utils.escape_html(code)}"
        end
      end

      # This can be overwritten in ApplicationController to disable query
      # tracking separately from peek
      def peek_activerecord_enabled?
        peek_enabled?
      end

      def inject_peek_activerecord(&block)
        return block.call unless peek_activerecord_enabled?
        ret = nil
        queries = []
        subscriber = ActiveSupport::Notifications.subscribe "sql.active_record" do |*args|
          event = ActiveSupport::Notifications::Event.new *args
          queries << event
        end
        ret = block.call
        peek_activerecord_append_queries_to_response(queries)
        ret
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
      end

      def peek_activerecord_append_queries_to_response(queries)
        if response.content_type =~ %r|text/html|
          output = <<-EOS
            <div class='ar_instrumentation' id='peek_activerecord_table'>
              <table class='table table-borderless'>
                <thead>
                  <tr>
                    <th class=duration-header>
                      Duration
                    </th>
                    <th class=cached-header>
                      Cached
                    </th>
                    <th class=sql-header>
                      SQL
                    </th>
                  </tr>
                </thead>
                <tbody>
          EOS
          queries.each do |query|
            output << <<-EOS
              <tr>
                <td class=duration-data>
                  #{"%.3f" % query.duration}ms
                </td>
                <td class=cache-data>
                  #{query.payload[:name] == "CACHE"}
                </td>
                <td class=sql-data>
                  #{pygmentized_sql(query.payload[:sql])}
                </td>
              </tr>
            EOS
          end
          output << "</tbody></table>"

          response.body += <<~EOF.html_safe
          <div class="modal fade" id="activeRecordQueriesModal" tabindex="-1" role="dialog" aria-labelledby="activeRecordQueriesModalTitle" aria-hidden="true">
            <div class="modal-dialog modal-xl modal-dialog-scrollable" role="document">
              <div class="modal-content">
                <div class="modal-header">
                  <h5 class="modal-title" id="activeRecordQueriesModalTitle">ActiveRecord Queries</h5>
                  <button type="button" class="close" data-dismiss="modal" aria-label="Close">
                    <span aria-hidden="true">&times;</span>
                  </button>
                </div>
                <div class="modal-body">
                  #{output}
                </div>
              </div>
            </div>
          </div>
          EOF
        end
      end
    end
  end
end
