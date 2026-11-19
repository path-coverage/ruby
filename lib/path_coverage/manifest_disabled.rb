module PathCoverage
  # The lines of a source not analysed: those between a
  # # path: disable comment and the next # path: enable, the
  # line straight after each disable saying why on a # reason:
  # line. Only a comment that is its line's whole text is a
  # marker, so a string or heredoc holding the text is not.
  module ManifestDisabled
    DISABLE = '# path: disable'.freeze
    ENABLE = '# path: enable'.freeze
    REASON = '# reason:'.freeze

    # The line numbers not analysed in source, at path, parsed as
    # parsed; ArgumentError naming a disable with no reason line
    # straight after it, or with no enable after it, or a
    # statement starting on such a line and ending after it.
    def self.lines(source, parsed, path)
      texts = source.lines
      found = markers(parsed.comments, texts)
      require_reasons(found, texts, path)
      disabled = between(found, path)
      refuse_straddling(parsed.value, disabled, path)
      disabled
    end

    # [line number, DISABLE or ENABLE] of each comment, of those,
    # that is one of them and its line's whole text, in order.
    def self.markers(comments, texts)
      comments.filter_map do |comment|
        number = comment.location.start_line
        text = texts[number - 1].strip
        [number, text] if [DISABLE, ENABLE].include?(text)
      end
    end

    # Refuses each DISABLE among found whose next line, of texts,
    # is no REASON line.
    def self.require_reasons(found, texts, path)
      found.each do |number, text|
        next unless text == DISABLE
        # texts[number] is the next line, nil after the last.
        next if texts[number].to_s.strip.start_with?(REASON)

        raise ArgumentError, "#{path}:#{number} #{DISABLE} needs " \
                             "a #{REASON} line straight after it"
      end
    end

    # The line numbers between each DISABLE among found and the
    # next marker; refuses a DISABLE with no marker after it.
    def self.between(found, path)
      disabled = Set.new
      opened = nil
      found.each do |number, text|
        disabled.merge((opened + 1)...number) if opened
        opened = text == DISABLE ? number : nil
      end
      return disabled unless opened

      raise ArgumentError,
            "#{path}:#{opened} #{DISABLE} has no #{ENABLE} after it"
    end

    # Refuses the first statement under tree that starts on a
    # disabled line and ends on an analysed one, as a statement
    # is analysed whole or not at all.
    def self.refuse_straddling(tree, disabled, path)
      found = straddler(tree, disabled)
      return unless found

      raise ArgumentError, "#{path}:#{found.location.start_line} " \
                           'the statement starting here ends ' \
                           "after its #{ENABLE}"
    end

    # The first statement under node that starts on one of the
    # disabled lines and ends on an analysed one, else nil.
    def self.straddler(node, disabled)
      statements = node.is_a?(Prism::StatementsNode) ? node.body : []
      statements.each do |statement|
        return statement if straddles?(statement, disabled)
      end
      node.compact_child_nodes.each do |child|
        found = straddler(child, disabled)
        return found if found
      end
      nil
    end

    # True for a statement starting on a disabled line and
    # ending on an analysed one.
    def self.straddles?(statement, disabled)
      location = statement.location
      disabled.include?(location.start_line) &&
        !disabled.include?(location.end_line)
    end
  end
end
