# Hugo Translator

An automated Hugo blog post translation tool based on [h7ml/ai-file-translator](https://github.com/h7ml/ai-file-translator) for multi-language content translation.

## Features

- Supports automatic translation of Chinese (zh-cn) blog posts into multiple target languages
- Default support for translation to English (en), Japanese (ja), Korean (ko), and more
- Intelligently skips already translated files, only processing untranslated content
- Supports supplementary translation for partially translated files
- Provides detailed translation progress statistics

## Prerequisites

- Node.js and npm
- Hugo blog project
- OpenAI API key (optional)

## Usage

1. Ensure you have a `content/posts` directory in your Hugo blog project
2. Place the `translate-posts.sh` script in the project root directory
3. Add execution permission:
   ```bash
   chmod +x translate-posts.sh
   ```
4. Run the translation script:
   ```bash
   ./translate-posts.sh
   ```

## Environment Variables

You can customize the translation behavior by setting the following environment variables:

- `TARGET_LANGS`: List of target languages, space-separated
  ```bash
  export TARGET_LANGS="en ja ko"
  ```
- `OPENAI_API_KEY`: OpenAI API key
  ```bash
  export OPENAI_API_KEY="your-api-key"
  ```
- `OPENAI_MODEL`: OpenAI model to use (default: gpt-3.5-turbo)
  ```bash
  export OPENAI_MODEL="gpt-4"
  ```

## Notes

- The script will automatically install the required `ai-markdown-translator` tool
- Uses Chinese (zh-cn) as the default source language
- Displays colorized progress output during translation
- Includes error handling and logging support

## License

MIT