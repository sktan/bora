require 'bora/cfn/stack'

class Bora
  module Resolver
    class Localfile
      FileDoesntExist = Class.new(StandardError)
      InvalidParameter = Class.new(StandardError)

      def initialize(stack)
        @stack = stack
        @stack_cache = {}
      end

      def resolve(uri)
        file_contents = nil
        if File.file?(uri.query)
            file_contents = File.read(uri.query)
        else
            raise FileDoesntExist, "Could not load file #{uri.query} for reading"
        end
        file_contents
      end
    end
  end
end
