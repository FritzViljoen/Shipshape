# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `io-is-its-own-kind` (docs/laws/io-is-its-own-kind.md).
      #
      # **The call matrix cannot see this.** It stops a command reaching `io_command` and
      # `io_query`, which are the kinds that talk to the outside — but `Net::HTTP` belongs to
      # a gem, resolves to no file under any declared glob, and is therefore skipped. So the
      # rule held for IO an application had filed as a kind and not for IO written inline,
      # which is the form it actually arrives in.
      #
      # **The cost is the transaction.** A command is exactly one transaction, opened by the
      # base class before `call` runs. An HTTP request inside it holds a database connection
      # open across a network round trip — for a timeout, for a retry, for however long the
      # far end takes. A query is worse: it has no transaction to blame, so a slow call there
      # is a read nobody thinks twice about.
      #
      # **The list is the fact, not a description of one.** Being named here is what makes a
      # constant IO; nothing infers it. That is why it cannot go stale — a client this list
      # does not know is invisible rather than wrongly classified, and an application adds its
      # own vendors to `Constants`.
      #
      # WHAT IT DOES NOT CATCH: a client the list does not name — every vendor SDK, and every
      # wrapper an application wrote around one. IO reached through a local or handed in as a
      # collaborator, since there is no constant to read. And the filesystem: `File` and `Dir`
      # are deliberately absent from the defaults, because `File.join` is a string operation
      # and separating it from `File.read` needs a per-constant method list that would drift.
      # An application that wants them adds them. **Tests are exempt.**
      #
      # @example
      #   # bad — in a command, which is holding a transaction open across the network
      #   class SettleInvoice < Command
      #     def call
      #       Net::HTTP.post(uri, body)
      #     end
      #   end
      #
      #   # good — the call is its own operation, and a workflow sequences the two
      #   class ChargeCard < IoCommand
      #     def call
      #       success(Net::HTTP.post(uri, body))
      #     end
      #   end
      class IoIsItsOwnKind < Base
        include ReadsKinds

        # The standard library's own networking, plus the HTTP clients a Rails application is
        # most likely to already have. Every message to one of these is a call to the outside.
        CONSTANTS = %w[
          Net::HTTP Net::HTTPS Net::FTP Net::SMTP Net::IMAP Net::POP3 Net::Telnet
          Socket TCPSocket UDPSocket UNIXSocket BasicSocket
          OpenURI Faraday RestClient HTTParty Excon Typhoeus Curl Curl::Easy HTTPX HTTPClient
        ].freeze

        def on_send(node)
          receiver = node.receiver
          return unless receiver&.const_type?
          return unless one_of?(governed_kinds)

          name = receiver.source.sub(/\A::/, "")
          return unless io_constants.include?(name)

          add_offense(receiver, message: message_for(name, node.method_name))
        end

        alias on_csend on_send

        private

        def message_for(name, message)
          explain(
            "`#{name}.#{message}` talks to the outside, and #{article} does not.",
            because: "A command is exactly one transaction, opened before `call` runs — so a " \
                     "network round trip inside one holds a database connection for as long " \
                     "as the far end takes, including its timeout and its retries. The call " \
                     "matrix cannot refuse this: `#{name}` belongs to a gem, resolves to no " \
                     "file under any declared glob, and is skipped. So the rule held for IO " \
                     "filed as a kind and not for IO written inline, which is the form it " \
                     "arrives in.",
            instead: <<~RUBY,
              # the call is its own operation, in the kind that has accepted the bill for it
              class ChargeCard < IoCommand
                def call
                  success(Net::HTTP.post(uri, body))
                end
              end

              # and a workflow sequences the outside call and the local write, which is the
              # only kind obliged to make each step idempotent
              class SettleInvoice < Workflow
                def call
                  charged = ChargeCard.call(actor: actor, invoice_id: @id)
                  return charged if charged.failure?

                  RecordPayment.call(actor: actor, invoice_id: @id)
                end
              end
            RUBY
          )
        end

        def article
          kind = kind_of_inspected_file.to_s.tr("_", " ")

          "a#{'n' if kind.start_with?('i', 'e', 'o')} #{kind}"
        end

        def io_constants
          @io_constants ||= cop_config.fetch("Constants", CONSTANTS)
        end

        # Everything except the kinds whose job is the outside, and the legacy doors, which
        # wrap an old world this canon has not classified.
        def governed_kinds
          cop_config.fetch(
            "Kinds",
            %w[workflow command query shape view_component record request_handling entry_point],
          )
        end
      end
    end
  end
end
