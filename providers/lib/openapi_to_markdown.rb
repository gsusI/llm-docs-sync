#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "fileutils"
require "date"

spec_path, out_dir, source_url, generated_at, title = ARGV

unless spec_path && out_dir && source_url && generated_at
  warn "Usage: openapi_to_markdown.rb SPEC_PATH OUT_DIR SOURCE_URL GENERATED_AT [TITLE]"
  exit 2
end

raw = File.read(spec_path)

# YAML parser can read JSON too.
spec = YAML.safe_load(
  raw,
  aliases: true,
  permitted_classes: [Date, Time]
)

info = spec["info"] || {}
paths = spec["paths"] || {}

title ||= info["title"] || "OpenAPI reference"

HTTP_METHODS = %w[get put post delete patch options head trace].freeze

def slugify(value)
  slug = value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  slug.empty? ? "misc" : slug
end

def titleize(value)
  value.to_s.split(/[_\-\s]+/).reject(&:empty?).map { |part| part[0].to_s.upcase + part[1..].to_s }.join(" ")
end

def deref(spec, obj)
  return obj unless obj.is_a?(Hash) && obj["$ref"].is_a?(String)
  ref = obj["$ref"]
  return obj unless ref.start_with?("#/")

  ref.split("/")[1..].reduce(spec) do |acc, key|
    acc.is_a?(Hash) ? acc[key] : nil
  end || obj
end

def schema_label(schema)
  return "" unless schema.is_a?(Hash)
  return "ref: #{schema["$ref"].split("/").last}" if schema["$ref"]

  if schema["oneOf"]
    labels = schema["oneOf"].map { |entry| schema_label(entry) }.reject(&:empty?)
    return labels.empty? ? "oneOf" : "oneOf: #{labels.join(", ")}" 
  end

  if schema["anyOf"]
    labels = schema["anyOf"].map { |entry| schema_label(entry) }.reject(&:empty?)
    return labels.empty? ? "anyOf" : "anyOf: #{labels.join(", ")}" 
  end

  if schema["allOf"]
    labels = schema["allOf"].map { |entry| schema_label(entry) }.reject(&:empty?)
    return labels.empty? ? "allOf" : "allOf: #{labels.join(", ")}" 
  end

  type = schema["type"]
  return "" unless type

  if type == "array"
    item = schema_label(schema["items"])
    return item.empty? ? "array" : "array of #{item}"
  end

  if type == "object"
    props = schema["properties"]&.keys
    if props && !props.empty?
      return "object{#{props.join(", ")}}"
    end
  end

  type.to_s
end

def format_description(text)
  return "" if text.nil?
  text.to_s.strip
end

def default_group_for_path(path)
  seg = path.to_s.split("/").reject(&:empty?).first
  seg.nil? || seg.empty? ? "misc" : seg
end

operations = []

paths.each do |path, path_item|
  next unless path_item.is_a?(Hash)

  path_params = path_item["parameters"] || []

  path_item.each do |method, op|
    next unless HTTP_METHODS.include?(method)
    next unless op.is_a?(Hash)

    meta = op["x-oaiMeta"] || {}
    tags = op["tags"].is_a?(Array) ? op["tags"] : []

    group = meta["group"] || tags.first || default_group_for_path(path)

    name = meta["name"] || op["summary"] || op["operationId"] || "#{method.upcase} #{path}"

    params = (path_params + (op["parameters"] || [])).uniq do |param|
      if param.is_a?(Hash)
        [param["name"], param["in"], param["$ref"]]
      else
        param
      end
    end

    operations << {
      group: group,
      name: name,
      method: method,
      path: path,
      op: op,
      meta: meta,
      params: params
    }
  end
end

groups = operations.group_by { |operation| operation[:group].to_s }

out_groups_dir = File.join(out_dir, "groups")
FileUtils.mkdir_p(out_groups_dir)

index_path = File.join(out_dir, "index.md")
File.open(index_path, "w") do |file|
  file.puts "# #{title}"
  file.puts "Source: #{source_url}"
  file.puts "Generated: #{generated_at}"
  file.puts "OpenAPI: #{spec["openapi"]}" if spec["openapi"]
  file.puts "Version: #{info["version"]}" if info["version"]
  file.puts
  file.puts "## Groups"
  groups.keys.sort.each do |group|
    slug = slugify(group)
    display = titleize(group)
    count = groups[group].length
    file.puts "- [#{display}](groups/#{slug}.md) (#{count} operations)"
  end
end

groups.each do |group, ops|
  slug = slugify(group)
  display = titleize(group)
  path = File.join(out_groups_dir, "#{slug}.md")

  File.open(path, "w") do |file|
    file.puts "# #{display}"
    file.puts "Source: #{source_url}"
    file.puts "Generated: #{generated_at}"
    file.puts

    ops.sort_by { |op| [op[:path], op[:method]] }.each do |operation|
      method = operation[:method].upcase
      path_value = operation[:path]
      op = operation[:op]
      meta = operation[:meta]
      params = operation[:params]

      file.puts "## #{operation[:name]}"
      file.puts "`#{method} #{path_value}`"
      file.puts

      summary = format_description(op["summary"])
      description = format_description(op["description"])
      file.puts summary unless summary.empty?
      file.puts if !summary.empty? && !description.empty?
      file.puts description unless description.empty?

      if op["deprecated"]
        file.puts
        file.puts "**Deprecated:** true"
      end

      if meta["beta"]
        file.puts
        file.puts "**Beta:** true"
      end

      returns = format_description(meta["returns"])
      unless returns.empty?
        file.puts
        file.puts "**Returns:** #{returns}"
      end

      unless params.empty?
        file.puts
        file.puts "### Parameters"
        params.each do |param|
          param_obj = deref(spec, param)
          name = param_obj["name"] || (param.is_a?(Hash) && param["$ref"] ? param["$ref"].split("/").last : "unknown")
          location = param_obj["in"] || "unknown"
          required = param_obj["required"] ? "required" : "optional"
          schema = schema_label(param_obj["schema"])
          description = format_description(param_obj["description"])

          line = "- `#{name}` (#{location}, #{required})"
          line += " `#{schema}`" unless schema.to_s.empty?
          line += ": #{description}" unless description.empty?
          file.puts line
        end
      end

      if op["requestBody"]
        request_body = deref(spec, op["requestBody"])
        content = request_body["content"] || {}
        unless content.empty?
          file.puts
          file.puts "### Request body"
          content.each do |content_type, content_obj|
            schema = schema_label(deref(spec, content_obj["schema"] || {}))
            line = "- `#{content_type}`"
            line += " `#{schema}`" unless schema.empty?
            file.puts line
          end
        end
      end

      responses = op["responses"] || {}
      unless responses.empty?
        file.puts
        file.puts "### Responses"
        responses.keys.sort.each do |status|
          response = deref(spec, responses[status]) || {}
          desc = format_description(response["description"])
          line = "- `#{status}`"
          line += ": #{desc}" unless desc.empty?

          content = response["content"] || {}
          if content.any?
            schemas = content.map do |content_type, content_obj|
              schema = schema_label(deref(spec, content_obj["schema"] || {}))
              schema.empty? ? "`#{content_type}`" : "`#{content_type}` (#{schema})"
            end
            line += " (#{schemas.join(", ")})"
          end

          file.puts line
        end
      end

      # OpenAI-style vendor examples; harmless when absent.
      examples = meta["examples"]
      request_examples = nil
      response_example = nil

      if examples.is_a?(Hash)
        request_examples = examples["request"]
        response_example = examples["response"]
      elsif examples
        response_example = examples
      end

      if request_examples || response_example
        file.puts
        file.puts "### Examples"
      end

      if request_examples.is_a?(Hash)
        request_examples.each do |label, code|
          lang = case label
                 when "curl" then "bash"
                 when "python" then "python"
                 when "node.js", "javascript" then "javascript"
                 else "text"
                 end
          file.puts
          file.puts "#### #{label}"
          file.puts "```#{lang}"
          file.puts code.to_s.rstrip
          file.puts "```"
        end
      elsif request_examples
        file.puts
        file.puts "#### request"
        file.puts "```text"
        file.puts request_examples.to_s.rstrip
        file.puts "```"
      end

      if response_example
        file.puts
        file.puts "#### response"
        file.puts "```json"
        file.puts response_example.to_s.rstrip
        file.puts "```"
      end

      file.puts
    end
  end
end
