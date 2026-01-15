#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: providers/openai.sh [--output DIR] [--index-url URL] [--spec-url URL]

Fetch the OpenAI API reference by reading the OpenAI llms.txt index to find the
OpenAPI spec, then generate Markdown reference files into the output directory.
USAGE
}

OUTPUT_DIR="openai-api-docs"
INDEX_URL="https://platform.openai.com/llms.txt"
SPEC_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --index-url)
      INDEX_URL="${2:-}"
      shift 2
      ;;
    --spec-url)
      SPEC_URL="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

for cmd in curl mktemp rg ruby sort head; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "$OUTPUT_DIR" = /* ]]; then
  OUT_DIR="$OUTPUT_DIR"
else
  OUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
fi

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "[openai] Downloading llms.txt index from $INDEX_URL"
CURL_BASE=(curl -fsSL --retry 3 --retry-delay 1 --retry-connrefused --http1.1)
"${CURL_BASE[@]}" "$INDEX_URL" -o "$WORKDIR/llms.txt"

if [[ -z "$SPEC_URL" ]]; then
  SPEC_URL="$(rg -o "https://platform.openai.com/docs/static/api-definition\\.ya?ml" "$WORKDIR/llms.txt" | head -n 1 || true)"
fi

if [[ -z "$SPEC_URL" ]]; then
  SPEC_URL="https://platform.openai.com/docs/static/api-definition.yaml"
fi

echo "[openai] Downloading OpenAPI spec from $SPEC_URL"
"${CURL_BASE[@]}" "$SPEC_URL" -o "$WORKDIR/api-definition.yaml"

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
mkdir -p "$OUT_DIR"

CONVERTER="$WORKDIR/convert-openai-api.rb"
cat > "$CONVERTER" <<'RUBY'
require "yaml"
require "fileutils"

spec_path, out_dir, source_url, generated_at = ARGV
spec = YAML.load_file(spec_path)

info = spec["info"] || {}
paths = spec["paths"] || {}

HTTP_METHODS = %w[get put post delete patch options head trace].freeze

def slugify(value)
  slug = value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  slug.empty? ? "misc" : slug
end

def titleize(value)
  value.to_s.split(/[_-]/).map { |part| part.capitalize }.join(" ")
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
    return "oneOf: " + schema["oneOf"].map { |entry| schema_label(entry) }.reject(&:empty?).join(", ")
  end

  if schema["anyOf"]
    return "anyOf: " + schema["anyOf"].map { |entry| schema_label(entry) }.reject(&:empty?).join(", ")
  end

  if schema["allOf"]
    return "allOf: " + schema["allOf"].map { |entry| schema_label(entry) }.reject(&:empty?).join(", ")
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

operations = []

paths.each do |path, path_item|
  next unless path_item.is_a?(Hash)
  path_params = path_item["parameters"] || []

  path_item.each do |method, op|
    next unless HTTP_METHODS.include?(method)
    next unless op.is_a?(Hash)

    meta = op["x-oaiMeta"] || {}
    group = meta["group"] || (op["tags"] && op["tags"].first) || "misc"
    name = meta["name"] || op["summary"] || "#{method.upcase} #{path}"
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
      params: params,
      path_item: path_item
    }
  end
end

groups = operations.group_by { |operation| operation[:group].to_s }

groups_dir = File.join(out_dir, "groups")
FileUtils.mkdir_p(groups_dir)

index_path = File.join(out_dir, "index.md")
File.open(index_path, "w") do |file|
  file.puts "# OpenAI API reference"
  file.puts "Source: #{source_url}"
  file.puts "Generated: #{generated_at}"
  file.puts "OpenAPI: #{spec["openapi"]}" if spec["openapi"]
  file.puts "Version: #{info["version"]}" if info["version"]
  file.puts
  file.puts "## Groups"
  groups.keys.sort.each do |group|
    slug = slugify(group)
    title = titleize(group)
    count = groups[group].length
    file.puts "- [#{title}](groups/#{slug}.md) (#{count} operations)"
  end
end

groups.each do |group, ops|
  slug = slugify(group)
  title = titleize(group)
  path = File.join(groups_dir, "#{slug}.md")

  File.open(path, "w") do |file|
    file.puts "# #{title}"
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
          line += " `#{schema}`" unless schema.empty()
          line += ": #{description}" unless description.empty()
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
          description = format_description(response["description"])
          line = "- `#{status}`"
          line += ": #{description}" unless description.empty?

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
RUBY

ruby "$CONVERTER" "$WORKDIR/api-definition.yaml" "$OUT_DIR" "$SPEC_URL" "$timestamp"

echo "[openai] Wrote API reference into $OUT_DIR"
