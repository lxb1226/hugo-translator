#!/bin/bash

# translate-posts.sh
# Script to automate translation of blog posts using h7ml/ai-file-translator
# Uses zh-cn as the source language and translates to specified target languages
# Supports both single-language and multi-language translation files
# Default target languages: English (en), Spanish (es), French (fr), Japanese (ja), Korean (ko)
# 
# BEHAVIOR:
# - Processes ALL files in the posts directory
# - Skips individual translations that already exist
# - Creates missing translations for files that are partially translated
# - Tracks detailed statistics of processed files and translations

# Strict mode
set -euo pipefail

# Default configuration
SOURCE_LANG="zh-cn"
POSTS_DIR="content/posts"

# Default target languages if not set via environment variable
# Initialize TARGET_LANGS as an empty array first to avoid unbound variable errors
declare -a TARGET_LANGS=()

# Check if TARGET_LANGS is set in the environment
if [ -z "${TARGET_LANGS+x}" ]; then
  # Not set, use defaults
  # TARGET_LANGS=("en" "es" "fr" "ja" "ko") # Default to English, Spanish, French, Japanese, Korean
  TARGET_LANGS=("en" "zh-cn" "ja" "ko") # Default to English, Spanish, French, Japanese, Korean
else
  # TARGET_LANGS is set in the environment
  # Check if it's a string (not already an array)
  if [[ ! "$(declare -p TARGET_LANGS 2>/dev/null)" =~ "declare -a" ]]; then
    # Convert the string to an array
    IFS=' ' read -r -a TARGET_LANGS_TEMP <<< "$TARGET_LANGS"
    TARGET_LANGS=("${TARGET_LANGS_TEMP[@]}")
  fi
fi

# Ensure the array is not empty
if [ ${#TARGET_LANGS[@]} -eq 0 ]; then
  TARGET_LANGS=("en" "es" "fr" "ja" "ko") # Fallback to defaults if empty
fi

# OpenAI API Configuration
# If not set, we'll rely on the tool's defaults or configuration file
OPENAI_API_KEY=${OPENAI_API_KEY:-""}
OPENAI_MODEL=${OPENAI_MODEL:-"gpt-3.5-turbo"}

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions for logging
log_error() {
  echo -e "${RED}ERROR:${NC} $1" >&2
}

log_success() {
  echo -e "${GREEN}SUCCESS:${NC} $1" >&2
}

log_info() {
  echo -e "${BLUE}INFO:${NC} $1" >&2
}

log_warning() {
  echo -e "${YELLOW}WARNING:${NC} $1" >&2
}

# Generic log function that writes to stderr
log() {
  echo "$@" >&2
}

# Function to check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."
  
  # Check if npm is installed
  if ! command -v npm &> /dev/null; then
    log_error "npm is not installed. Please install Node.js and npm first."
    exit 1
  fi
  
  # Check if posts directory exists
  if [ ! -d "$POSTS_DIR" ]; then
    log_error "Posts directory '$POSTS_DIR' does not exist"
    exit 1
  fi
  
  # Install ai-markdown-translator if not already installed
  if ! command -v npx ai-markdown-translator &> /dev/null; then
    log_info "Installing ai-markdown-translator globally..."
    npm install -g ai-markdown-translator
    
    # Check if installation was successful
    if ! command -v ai-markdown-translator &> /dev/null; then
      log_error "Failed to install ai-markdown-translator"
      log_info "Try installing manually: npm install -g ai-markdown-translator"
      exit 1
    fi
  fi
  
  # Warn if OPENAI_API_KEY is not set
  if [ -z "$OPENAI_API_KEY" ]; then
    log_warning "OPENAI_API_KEY is not set. Make sure it's configured in your environment or .env file"
    log_info "Example: export OPENAI_API_KEY='your-api-key'"
  else
    log_success "OPENAI_API_KEY is set"
  fi
  
  log_success "All prerequisites met"
}

# Function to get base name from filename
# Example: input "how-to-use-mess-auto.zh-cn.md" -> output "how-to-use-mess-auto"
# Example: input "how-to-use-mess-auto.en es fr.md" -> output "how-to-use-mess-auto"
get_base_name() {
  local filename=$(basename "$1")
  # Get the portion before the first dot
  echo "$filename" | cut -d. -f1
}

# Function to extract the source language from a filename
# Example: input "how-to-use-mess-auto.zh-cn.md" -> output "zh-cn"
# Example: input "how-to-use-mess-auto.en es fr.md" -> output "en"
get_source_lang_from_filename() {
  local filename=$(basename "$1")
  # Get the portion after the first dot and before the next space or dot
  echo "$filename" | cut -d. -f2 | cut -d' ' -f1
}

# Function to extract target languages from a filename
# Example: input "how-to-use-mess-auto.en es fr.md" -> output "es fr"
# Example: input "how-to-use-mess-auto.en.md" -> output ""
get_target_langs_from_filename() {
  local filename=$(basename "$1")
  local extension_part=$(echo "$filename" | cut -d. -f2-)
  
  # Check if there are spaces in the extension part, indicating multiple languages
  if [[ "$extension_part" == *" "* ]]; then
    # Get everything after the first language and before the file extension
    local langs_part=$(echo "$extension_part" | cut -d' ' -f2- | sed 's/\.md$//')
    echo "$langs_part"
  else
    # No additional languages in the filename
    echo ""
  fi
}

# Function to get the combined language suffix for a file
# Example: input filename "how-to-use-mess-auto.en es fr.md" -> output "en es fr"
get_lang_suffix() {
  local filename=$(basename "$1")
  # Get everything after the first dot and before the file extension
  echo "$filename" | cut -d. -f2- | sed 's/\.md$//'
}

# Function to check if a translation exists and is valid
check_translation_exists() {
  local base_name="$1"
  local lang="$2"
  local file="$POSTS_DIR/$base_name.$lang.md"
  
  # Check if file exists and is not empty
  if [ -f "$file" ] && [ -s "$file" ]; then
    return 0  # File exists and is not empty
  fi
  
  # Also check for multi-language files containing this language
  local multi_lang_files=("$POSTS_DIR/$base_name."*" $lang "*.md "$POSTS_DIR/$base_name."*" $lang.md")
  
  for multi_file in "${multi_lang_files[@]}"; do
    # Use ls to handle the glob pattern and avoid errors if no matches
    if ls $multi_file 1> /dev/null 2>&1; then
      for actual_file in $multi_file; do
        if [ -f "$actual_file" ] && [ -s "$actual_file" ]; then
          # Check if the file actually contains the language (not just part of another word)
          local lang_suffix=$(get_lang_suffix "$actual_file")
          local IFS=' '
          read -ra langs <<< "$lang_suffix"
          for l in "${langs[@]}"; do
            if [ "$l" = "$lang" ]; then
              return 0  # Found language in a multi-language file
            fi
          done
        fi
      done
    fi
  done
  
  return 1  # Language translation doesn't exist
}

# Function to check if a multi-language translation file exists
check_multi_translation_exists() {
  local base_name="$1"
  local langs="$2"  # Space-separated list of languages
  local file="$POSTS_DIR/$base_name.$langs.md"
  
  # Check if file exists and is not empty
  if [ -f "$file" ] && [ -s "$file" ]; then
    return 0  # File exists and is not empty
  fi
  
  return 1  # File doesn't exist or is empty
}

# Function to translate a single file to a target language
translate_file() {
  local source_file="$1"
  local target_lang="$2"
  local base_name=$(get_base_name "$source_file")
  local target_file="$POSTS_DIR/$base_name.$target_lang.md"
  
  # Check if translation already exists and is valid
  if check_translation_exists "$base_name" "$target_lang"; then
    log_info "Skipping $base_name.$target_lang.md (already exists)"
    return 2  # Return code 2 means skipped
  fi
  
  log_info "Translating $base_name from $SOURCE_LANG to $target_lang..."
  
  # Log more detailed progress information
  log_info "📝 Preparing translation of $base_name.$SOURCE_LANG.md to $target_lang..."
  
  # Prepare command based on whether API key is provided
  local cmd_args=()
  cmd_args+=(--input "$source_file")
  cmd_args+=(--output "$target_file")
  cmd_args+=(-l "$target_lang")
  
  if [ -n "$OPENAI_API_KEY" ]; then
    cmd_args+=(--api-key "$OPENAI_API_KEY")
    cmd_args+=(--model "$OPENAI_MODEL")
  fi
  
  # Execute translation
  log_info "🔄 Starting translation for $base_name to $target_lang..."
  if npx ai-markdown-translator "${cmd_args[@]}"; then
    log_success "✅ Created $base_name.$target_lang.md"
    return 0  # Successfully translated
  else
    log_error "❌ Failed to translate $base_name to $target_lang"
    return 1  # Error translating
  fi
}

# Function to translate a file to multiple target languages and combine into one file
translate_file_multi() {
  local source_file="$1"
  local target_langs="$2"  # Space-separated list of target languages
  local base_name=$(get_base_name "$source_file")
  local source_lang=$(get_source_lang_from_filename "$source_file")
  local target_file="$POSTS_DIR/$base_name.$source_lang $target_langs.md"
  
  # Check if multi-language translation already exists
  if check_multi_translation_exists "$base_name" "$source_lang $target_langs"; then
    log_info "Skipping $base_name.$source_lang $target_langs.md (already exists)"
    return 2  # Return code 2 means skipped
  fi
  
  log_info "Translating $base_name from $source_lang to multiple languages: $target_langs..."
  
  # Create an array from space-separated languages
  local IFS=' '
  read -ra lang_array <<< "$target_langs"
  
  # For now, we'll translate one language at a time and combine the results
  # This could be optimized in the future to use a single API call if the tool supports it
  local all_success=true
  local temp_files=()
  
  for lang in "${lang_array[@]}"; do
    local temp_file=$(mktemp)
    temp_files+=("$temp_file")
    
    log_info "📝 Preparing translation of $base_name.$source_lang.md to $lang..."
    
    # Prepare command based on whether API key is provided
    local cmd_args=()
    cmd_args+=(--input "$source_file")
    cmd_args+=(--output "$temp_file")
    cmd_args+=(-l "$lang")
    
    if [ -n "$OPENAI_API_KEY" ]; then
      cmd_args+=(--api-key "$OPENAI_API_KEY")
      cmd_args+=(--model "$OPENAI_MODEL")
    fi
    
    # Execute translation
    log_info "🔄 Starting translation for $base_name to $lang..."
    if ! npx ai-markdown-translator "${cmd_args[@]}"; then
      log_error "❌ Failed to translate $base_name to $lang"
      all_success=false
    fi
  done
  
  # Now combine all translations into a single file
  if [ "$all_success" = true ]; then
    # Copy the source file first
    cp "$source_file" "$target_file"
    
    # Append each translated file with appropriate section headers
    for i in "${!lang_array[@]}"; do
      local lang="${lang_array[$i]}"
      local temp_file="${temp_files[$i]}"
      
      echo -e "\n\n<!-- TRANSLATION: $lang -->\n" >> "$target_file"
      cat "$temp_file" >> "$target_file"
    done
    
    log_success "✅ Created combined translation file $base_name.$source_lang $target_langs.md"
    
    # Clean up temporary files
    for temp_file in "${temp_files[@]}"; do
      rm -f "$temp_file"
    done
    
    return 0  # Successfully translated
  else
    log_error "❌ Failed to create combined translation file"
    
    # Clean up temporary files
    for temp_file in "${temp_files[@]}"; do
      rm -f "$temp_file"
    done
    
    return 1  # Error translating
  fi
}

# Function to process a single source file for all target languages
# This function outputs counts as a simple colon-separated value to stdout
# All log messages are sent to stderr
process_source_file() {
  local source_file="$1"
  local base_name=$(get_base_name "$source_file")
  local all_exist=true
  local any_translated=false
  local any_error=false
  local skipped=0
  local translated=0
  local errors=0
  
  log_info "Processing $base_name..."
  
  # Check if this is a multi-language file
  local filename=$(basename "$source_file")
  local is_multi_lang=false
  local file_target_langs=()
  
  # Check if the filename contains spaces in the language part
  if [[ "$filename" == *"."*" "* ]]; then
    is_multi_lang=true
    # Extract target languages from filename
    file_target_langs=($(get_target_langs_from_filename "$source_file"))
    log_info "Detected multi-language file with target languages: ${file_target_langs[*]}"
  fi
  
  # If it's a multi-language file, use those languages, otherwise use TARGET_LANGS
  declare -a langs_to_process
  if [ "$is_multi_lang" = true ] && [ ${#file_target_langs[@]} -gt 0 ]; then
    langs_to_process=("${file_target_langs[@]}")
  else
    # First check which languages need translation
    for lang in "${TARGET_LANGS[@]}"; do
      if [ "$lang" = "$SOURCE_LANG" ]; then
        continue  # Skip source language
      fi
      
      if ! check_translation_exists "$base_name" "$lang"; then
        all_exist=false
        langs_to_process+=("$lang")
      else
        ((skipped++))
      fi
    done
    
    # If all translations exist, log that we're skipping this file
    if [ "$all_exist" = true ]; then
      log_info "Skipping $base_name (all translations exist)"
      # Return counts: 0 translations, all skipped, 0 errors
      # Safely get the array length with explicit check
      local target_langs_count=${#TARGET_LANGS[@]}
      printf "0:%d:0\n" "$target_langs_count"
      # Don't return here, let the function continue processing
    fi
  fi
  
  # If it's a multi-language file, process all languages together
  if [ "$is_multi_lang" = true ]; then
    log_info "➡️ Starting multi-language translation of $source_file to ${file_target_langs[*]}..."
    translate_file_multi "$source_file" "${file_target_langs[*]}"
    status=$?
    
    # Display progress
    case $status in
      0) 
        log_info "✅ Completed multi-language translation to ${file_target_langs[*]}" 
        ((translated+=1))
        any_translated=true
        ;;
      1) 
        log_info "❌ Failed multi-language translation" 
        ((errors+=1))
        any_error=true
        ;;
      2) 
        log_info "⏭️ Skipped multi-language translation (already exists)" 
        ((skipped+=1))
        ;;
    esac
  else
    # Process each target language individually
    if [ ${#langs_to_process[@]} -eq 0 ]; then
      log_info "No languages to process for $source_file"
      printf "0:%d:0\n" "$skipped"
      return 0
    fi
    
    for lang in "${langs_to_process[@]}"; do
      log_info "➡️ Starting translation of $source_file to $lang..."
      translate_file "$source_file" "$lang"
      status=$?
      
      # Display progress after each language translation
      case $status in
        0) log_info "✅ Completed translation to $lang" ;;
        1) log_info "❌ Failed translation to $lang" ;;
        2) log_info "⏭️ Skipped translation to $lang (already exists)" ;;
      esac
      
      if [ $status -eq 0 ]; then
        ((translated++))
        any_translated=true
      elif [ $status -eq 1 ]; then
        ((errors++))
        any_error=true
      elif [ $status -eq 2 ]; then
        ((skipped++))
      fi
    done
  fi
  
  # Return counts as a clean, machine-readable output (stdout)
  # Format: translated:skipped:errors
  printf "%d:%d:%d\n" "$translated" "$skipped" "$errors"
  
  # Set appropriate exit status
  # Only return error status if ALL translations failed
  # Otherwise return success to continue processing other files
  if [ "$translated" -eq 0 ] && [ "$errors" -gt 0 ]; then
    return 1  # All translations failed
  elif [ "$translated" -gt 0 ]; then
    return 0  # At least one translation succeeded
  else
    return 0  # All translations skipped, but continue processing
  fi
}

# Main function
main() {
  # Create a temporary log file
  local BUILD_LOG="/tmp/translate-posts-$$.log"  # Temporary log file
  
  # Enhanced statistics tracking
  local files_processed=0
  local files_with_new_translations=0
  local files_skipped=0
  local files_with_errors=0
  local files_need_translation=0
  local total_translated=0
  local total_skipped=0
  local total_errors=0
  
  # Print banner
  echo "========================================="
  echo "   Blog Post Translation Automation"
  echo "========================================="
  
  # Check prerequisites
  check_prerequisites
  
  # Print configuration
  log_info "Source language: $SOURCE_LANG"
  log_info "Target languages: ${TARGET_LANGS[*]}"
  log_info "Posts directory: $POSTS_DIR"
  log_info "OpenAI model: $OPENAI_MODEL"
  echo "----------------------------------------"
  
  # Find all source files - both standard and multi-language format
  local source_files_standard=("$POSTS_DIR"/*."$SOURCE_LANG".md)
  local source_files_multi=("$POSTS_DIR"/*."$SOURCE_LANG "*.md)
  local source_files=()
  
  # Add standard source files
  for file in "${source_files_standard[@]}"; do
    if [ -f "$file" ]; then
      source_files+=("$file")
    fi
  done
  
  # Add multi-language source files
  for file in "${source_files_multi[@]}"; do
    if [ -f "$file" ]; then
      source_files+=("$file")
    fi
  done
  
  # Check if any files were found
  if [ ${#source_files[@]} -eq 0 ]; then
    log_warning "No $SOURCE_LANG files found in $POSTS_DIR"
    exit 0
  fi
  
  log_info "Found ${#source_files[@]} $SOURCE_LANG files to process"
  
  # Process each source file
  for source_file in "${source_files[@]}"; do
    ((files_processed++))
    
    # Display clear file separator for better readability
    echo "----------------------------------------"
    log_info "🔄 Processing file $files_processed of ${#source_files[@]}: $(basename "$source_file")"
    
    # Check if this is a multi-language file
    if [[ "$(basename "$source_file")" == *"."*" "* ]]; then
      local target_langs=($(get_target_langs_from_filename "$source_file"))
      log_info "Multi-language file with target languages: ${target_langs[*]}"
    fi
    
    # Process the file and capture its output
    # Using tee to capture both the counts (stdout) and log messages
    # Redirecting to a temporary file first
    local temp_output=$(mktemp)
    
    # Ensure all output is displayed on screen while also being logged
    process_source_file "$source_file" 2>&1 | tee -a "$BUILD_LOG" | tee "$temp_output"
    local status=${PIPESTATUS[0]}
    
    # Extract the counts from the last line of the output
    local counts=$(grep -E "^[0-9]+:[0-9]+:[0-9]+$" "$temp_output" | tail -n 1)
    rm "$temp_output"  # Clean up the temporary file
    
    # Display file completion status
    case $status in
      0) log_success "✅ Completed file with new translations" ;;
      1) log_warning "⚠️ Completed file with some errors" ;;
      2) log_info "⏭️ Skipped file (all translations exist)" ;;
    esac
    
    # Parse the counts directly from the clean output format
    # Format is: translated:skipped:errors
    if [[ "$counts" =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]]; then
      local translated="${BASH_REMATCH[1]}"
      local skipped="${BASH_REMATCH[2]}"
      local errors="${BASH_REMATCH[3]}"
      
      # Accumulate counts
      ((total_translated+=translated))
      ((total_skipped+=skipped))
      ((total_errors+=errors))
    else
      log_error "Failed to parse count values for $source_file (got: '$counts')"
      ((total_errors+=1))
    fi
    
    # Count file status
    if [ $status -eq 0 ]; then
      ((files_with_new_translations++))
    elif [ $status -eq 1 ]; then
      ((files_with_errors++))
    else
      ((files_skipped++))
    fi
    
    # Check if the file actually had any new translations created
    if [ "$translated" -gt 0 ]; then
      ((files_need_translation++))
    fi
    done
    
    # Print summary
  echo "========================================="
  log_success "🎉 Translation complete!"
  log_info "📊 Summary:"
  log_info "  📁 Files processed: $files_processed"
  log_info "  📄 Files that needed translation: $files_need_translation"
  log_info "  ✅ Files with new translations: $files_with_new_translations"
  log_info "  ⏭️ Files skipped (all translations exist): $files_skipped"
  log_info "  ❌ Files with errors: $files_with_errors"
  echo "----------------------------------------"
  log_info "  📄 Total translations created: $total_translated"
  log_info "  🔄 Total translations skipped: $total_skipped"
  log_info "  ⚠️ Total translation errors: $total_errors"
  echo "========================================="
  
  # Clean up the temporary log file
  if [ -f "$BUILD_LOG" ]; then
    log_info "📋 Complete build log available at: $BUILD_LOG"
    
    # Check if there were errors and provide helpful tip
    if [ $total_errors -gt 0 ]; then
      log_info "💡 Tip: Check the build log for detailed error information"
    fi
  fi
  
  # Return non-zero exit code if there were errors
  [ $files_with_errors -eq 0 ]
}

# Execute main function
main
