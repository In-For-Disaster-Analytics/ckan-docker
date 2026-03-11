#!/usr/bin/env python3
"""
Extract CSS selectors that modify color or background-color properties.
Creates a new CSS file with only color-related rules.
"""

import re
import sys
import os

def extract_color_css(input_file, output_file):
    """
    Extract CSS rules that contain color or background-color properties.
    """
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            css_content = f.read()
    except FileNotFoundError:
        print(f"Error: File '{input_file}' not found")
        return False
    except Exception as e:
        print(f"Error reading file: {e}")
        return False

    # Remove CSS comments
    css_content = re.sub(r'/\*.*?\*/', '', css_content, flags=re.DOTALL)

    # Split CSS into rules (selector + declarations block)
    css_rules = re.findall(r'([^{}]+)\s*\{([^{}]*)\}', css_content)

    color_rules = []
    css_variables = []

    for selector, declarations in css_rules:
        selector = selector.strip()
        declarations = declarations.strip()

        # Special handling for :root - preserve all declarations
        if selector == ':root':
            # Keep all declarations in :root (CSS variables)
            clean_declarations = []
            for line in declarations.split(';'):
                line = line.strip()
                if line:
                    if not line.endswith(';'):
                        line += ';'
                    clean_declarations.append('  ' + line)
            
            if clean_declarations:
                css_variables.append(f"{selector} {{\n" + '\n'.join(clean_declarations) + "\n}")
        else:
            # For other selectors, check if this rule contains color-related properties
            color_properties = re.findall(
                r'((?:background-)?color|background|background-image|border(?:-(?:top|right|bottom|left|color))?)\s*:\s*[^;]+;?',
                declarations,
                re.IGNORECASE
            )

            if color_properties:
                # Clean up the selector and declarations
                clean_declarations = []
                for line in declarations.split(';'):
                    line = line.strip()
                    if line and re.search(r'((?:background-)?color|background|background-image|border(?:-(?:top|right|bottom|left|color))?)', line, re.IGNORECASE):
                        if not line.endswith(';'):
                            line += ';'
                        clean_declarations.append('  ' + line)

                if clean_declarations:
                    color_rules.append(f"{selector} {{\n" + '\n'.join(clean_declarations) + "\n}")

    # Write the extracted CSS
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write("/* Extracted color-related CSS rules */\n\n")

            # Write CSS variables first
            if css_variables:
                f.write("/* CSS Variables */\n")
                for rule in css_variables:
                    f.write(rule + "\n\n")

            # Write color rules
            if color_rules:
                f.write("/* Color Rules */\n")
                for rule in color_rules:
                    f.write(rule + "\n\n")

        print(f"✅ Extracted {len(css_variables)} variable rules and {len(color_rules)} color rules")
        print(f"✅ Output written to: {output_file}")
        return True

    except Exception as e:
        print(f"Error writing output file: {e}")
        return False

def main():
    # Default files
    input_file = "tacc_colors.css"
    output_file = "tacc_colors_extracted.css"

    # Check command line arguments
    if len(sys.argv) > 1:
        input_file = sys.argv[1]
    if len(sys.argv) > 2:
        output_file = sys.argv[2]

    # Check if input file exists
    if not os.path.exists(input_file):
        print(f"Input file '{input_file}' not found")
        print("Usage: python extract_colors.py [input.css] [output.css]")
        sys.exit(1)

    print(f"🔍 Extracting color rules from: {input_file}")
    print(f"📝 Output will be saved to: {output_file}")

    success = extract_color_css(input_file, output_file)

    if success:
        print("✨ Color extraction completed successfully!")
    else:
        print("❌ Color extraction failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()