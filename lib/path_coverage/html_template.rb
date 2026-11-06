require 'json'

module PathCoverage
  # The HTML report's pages, from a copy of the shared renderer,
  # html-reporter, kept beside this file: each page is page.html,
  # its data inline, drawn in the browser by render.js.
  module HtmlTemplate
    DIR = File.join(__dir__, 'html')

    # The text of one of the renderer's files.
    def self.asset(name)
      File.read(File.join(DIR, name))
    end

    # Example: PageData.index's data gives the index page.
    # The page drawing data, as PageData gives it: the template
    # pages.json names, its style the style sheet, its data the
    # data, and its script the scripts its kind of page runs.
    def self.page(data)
      pages = JSON.parse(asset('pages.json'))
      scripts = pages['scripts'].fetch(data[:page])
      fill(asset(pages['template']),
           'style' => asset(pages['style']),
           'data' => inline(data),
           'script' => scripts.map { asset(_1) }.join)
    end

    # Example: a text of </script> is written <\/script>.
    # data as JSON to put inside a script, every </ written <\/
    # so no string in it can close the script.
    def self.inline(data)
      JSON.generate(data).gsub('</', '<\/')
    end

    # template with each {{name}} replaced by values[name].
    def self.fill(template, values)
      template.gsub(/\{\{(\w+)\}\}/) do
        values.fetch(Regexp.last_match(1))
      end
    end
  end
end
