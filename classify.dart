// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * Kinds of tokens that we care to highlight differently. The values of the
 * fields here will be used as CSS class names for the generated spans.
 */
class Classification {
  static final NONE = null;
  static final ERROR = "e";
  static final COMMENT = "c";
  static final IDENTIFIER = "i";
  static final KEYWORD = "k";
  static final OPERATOR = "o";
  static final STRING = "s";
  static final NUMBER = "n";
  static final PUNCTUATION = "p";

  // A few things that are nice to make different:
  static final TYPE_IDENTIFIER = "t";

  // Between a keyword and an identifier
  static final SPECIAL_IDENTIFIER = "r";

  static final ARROW_OPERATOR = "a";

  static final STRING_INTERPOLATION = 'si';
}

String classifySource(SourceFile src) {
  var html = new StringBuffer();
  var tokenizer = new lang.Tokenizer(src, /*skipWhitespace:*/false);

  var token;
  var inString = false;
  while ((token = tokenizer.next()).kind != lang.TokenKind.END_OF_FILE) {

    // Track whether or not we're in a string.
    switch (token.kind) {
      case lang.TokenKind.STRING:
      case lang.TokenKind.STRING_PART:
      case lang.TokenKind.INCOMPLETE_STRING:
      case lang.TokenKind.INCOMPLETE_MULTILINE_STRING_DQ:
      case lang.TokenKind.INCOMPLETE_MULTILINE_STRING_SQ:
        inString = true;
        break;
    }

    final kind = classify(token);
    final text = md.escapeHtml(token.text);
    if (kind != null) {
      // Add a secondary class to tokens appearing within a string so that
      // we can highlight tokens in an interpolation specially.
      var stringClass = inString ? Classification.STRING_INTERPOLATION : '';
      html.add('<span class="$kind $stringClass">$text</span>');
    } else {
      html.add('<span>$text</span>');
    }

    // Track whether or not we're in a string.
    if (token.kind == lang.TokenKind.STRING) {
      inString = false;
    }
  }
  return html.toString();
}

bool _looksLikeType(String name) {
  // If the name looks like an UppercaseName, assume it's a type.
  return _looksLikePublicType(name) || _looksLikePrivateType(name);
}

bool _looksLikePublicType(String name) {
  // If the name looks like an UppercaseName, assume it's a type.
  return name.length >= 2 && isUpper(name[0]) && isLower(name[1]);
}

bool _looksLikePrivateType(String name) {
  // If the name looks like an _UppercaseName, assume it's a type.
  return (name.length >= 3 && name[0] == '_' && isUpper(name[1])
    && isLower(name[2]));
}

// These ensure that they don't return "true" if the string only has symbols.
bool isUpper(String s) => s.toLowerCase() != s;
bool isLower(String s) => s.toUpperCase() != s;

String classify(Token token) {
  switch (token.kind) {
    case lang.TokenKind.ERROR:
      return Classification.ERROR;

    case lang.TokenKind.IDENTIFIER:
      // Special case for names that look like types.
      if (_looksLikeType(token.text)
          || token.text == 'num'
          || token.text == 'bool'
          || token.text == 'int'
          || token.text == 'double') {
        return Classification.TYPE_IDENTIFIER;
      }
      return Classification.IDENTIFIER;

    // Even though it's a reserved word, let's try coloring it like a type.
    case lang.TokenKind.VOID:
      return Classification.TYPE_IDENTIFIER;

    case lang.TokenKind.THIS:
    case lang.TokenKind.SUPER:
      return Classification.SPECIAL_IDENTIFIER;

    case lang.TokenKind.STRING:
    case lang.TokenKind.STRING_PART:
    case lang.TokenKind.INCOMPLETE_STRING:
    case lang.TokenKind.INCOMPLETE_MULTILINE_STRING_DQ:
    case lang.TokenKind.INCOMPLETE_MULTILINE_STRING_SQ:
      return Classification.STRING;

    case lang.TokenKind.INTEGER:
    case lang.TokenKind.HEX_INTEGER:
    case lang.TokenKind.DOUBLE:
      return Classification.NUMBER;

    case lang.TokenKind.COMMENT:
    case lang.TokenKind.INCOMPLETE_COMMENT:
      return Classification.COMMENT;

    // => is so awesome it is in a class of its own.
    case lang.TokenKind.ARROW:
      return Classification.ARROW_OPERATOR;

    case lang.TokenKind.HASHBANG:
    case lang.TokenKind.LPAREN:
    case lang.TokenKind.RPAREN:
    case lang.TokenKind.LBRACK:
    case lang.TokenKind.RBRACK:
    case lang.TokenKind.LBRACE:
    case lang.TokenKind.RBRACE:
    case lang.TokenKind.COLON:
    case lang.TokenKind.SEMICOLON:
    case lang.TokenKind.COMMA:
    case lang.TokenKind.DOT:
    case lang.TokenKind.ELLIPSIS:
      return Classification.PUNCTUATION;

    case lang.TokenKind.INCR:
    case lang.TokenKind.DECR:
    case lang.TokenKind.BIT_NOT:
    case lang.TokenKind.NOT:
    case lang.TokenKind.ASSIGN:
    case lang.TokenKind.ASSIGN_OR:
    case lang.TokenKind.ASSIGN_XOR:
    case lang.TokenKind.ASSIGN_AND:
    case lang.TokenKind.ASSIGN_SHL:
    case lang.TokenKind.ASSIGN_SAR:
    case lang.TokenKind.ASSIGN_SHR:
    case lang.TokenKind.ASSIGN_ADD:
    case lang.TokenKind.ASSIGN_SUB:
    case lang.TokenKind.ASSIGN_MUL:
    case lang.TokenKind.ASSIGN_DIV:
    case lang.TokenKind.ASSIGN_TRUNCDIV:
    case lang.TokenKind.ASSIGN_MOD:
    case lang.TokenKind.CONDITIONAL:
    case lang.TokenKind.OR:
    case lang.TokenKind.AND:
    case lang.TokenKind.BIT_OR:
    case lang.TokenKind.BIT_XOR:
    case lang.TokenKind.BIT_AND:
    case lang.TokenKind.SHL:
    case lang.TokenKind.SAR:
    case lang.TokenKind.SHR:
    case lang.TokenKind.ADD:
    case lang.TokenKind.SUB:
    case lang.TokenKind.MUL:
    case lang.TokenKind.DIV:
    case lang.TokenKind.TRUNCDIV:
    case lang.TokenKind.MOD:
    case lang.TokenKind.EQ:
    case lang.TokenKind.NE:
    case lang.TokenKind.EQ_STRICT:
    case lang.TokenKind.NE_STRICT:
    case lang.TokenKind.LT:
    case lang.TokenKind.GT:
    case lang.TokenKind.LTE:
    case lang.TokenKind.GTE:
    case lang.TokenKind.INDEX:
    case lang.TokenKind.SETINDEX:
      return Classification.OPERATOR;

    // Color this like a keyword
    case lang.TokenKind.HASH:

    case lang.TokenKind.ABSTRACT:
    case lang.TokenKind.ASSERT:
    case lang.TokenKind.CLASS:
    case lang.TokenKind.EXTENDS:
    case lang.TokenKind.FACTORY:
    case lang.TokenKind.GET:
    case lang.TokenKind.IMPLEMENTS:
    case lang.TokenKind.IMPORT:
    case lang.TokenKind.INTERFACE:
    case lang.TokenKind.LIBRARY:
    case lang.TokenKind.NATIVE:
    case lang.TokenKind.NEGATE:
    case lang.TokenKind.OPERATOR:
    case lang.TokenKind.SET:
    case lang.TokenKind.SOURCE:
    case lang.TokenKind.STATIC:
    case lang.TokenKind.TYPEDEF:
    case lang.TokenKind.BREAK:
    case lang.TokenKind.CASE:
    case lang.TokenKind.CATCH:
    case lang.TokenKind.CONST:
    case lang.TokenKind.CONTINUE:
    case lang.TokenKind.DEFAULT:
    case lang.TokenKind.DO:
    case lang.TokenKind.ELSE:
    case lang.TokenKind.FALSE:
    case lang.TokenKind.FINALLY:
    case lang.TokenKind.FOR:
    case lang.TokenKind.IF:
    case lang.TokenKind.IN:
    case lang.TokenKind.IS:
    case lang.TokenKind.NEW:
    case lang.TokenKind.NULL:
    case lang.TokenKind.RETURN:
    case lang.TokenKind.SWITCH:
    case lang.TokenKind.THROW:
    case lang.TokenKind.TRUE:
    case lang.TokenKind.TRY:
    case lang.TokenKind.WHILE:
    case lang.TokenKind.VAR:
    case lang.TokenKind.FINAL:
      return Classification.KEYWORD;

    case lang.TokenKind.WHITESPACE:
    case lang.TokenKind.END_OF_FILE:
      return Classification.NONE;

    default:
      return Classification.NONE;
  }
}