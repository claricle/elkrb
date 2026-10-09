# frozen_string_literal: true

# Reads README.adoc the way a reader does: every `[source,ruby]` block that is
# followed by a `Prints:` paragraph and a `[source]` listing is one example,
# the listing being the output it promises.
module ReadmeExamples
  Example = Struct.new(:line, :code, :printed)

  FENCED = '(?:(?!^----$).*\n)*'

  RUBY_BLOCK = Regexp.new(
    "^\\[source,ruby\\]\n----\n(?<code>#{FENCED})----\n\n" \
    "Prints:\n\n\\[source\\]\n----\n(?<printed>#{FENCED})----$",
  )

  def readme_examples(path)
    text = File.read(path)
    text.to_enum(:scan, RUBY_BLOCK).map do
      match = Regexp.last_match
      Example.new(text[0...match.begin(:code)].count("\n") + 1,
                  match[:code], match[:printed])
    end
  end
end
