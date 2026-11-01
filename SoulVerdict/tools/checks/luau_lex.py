"""Small, dependency-free Luau lexer shared by the SoulVerdict static checks.

Handles everything that matters for not mis-reading code as text or text as code:
  -- line comments, --[[ ]] / --[==[ ]==] long comments, "..." / '...' strings with escapes
  (\\z, escaped newlines), [[ ]] / [=[ ]=] long strings, `interpolated {strings}` (the {expr}
  parts are lexed as code), numbers (hex, binary, _ separators, exponents), names, keywords and every
  Luau operator (//, //=, ..=, ->, ::, compound assignments).

API
  lex(source) -> Lexed
      .tokens        list[Tok]   (comments dropped; strings keep their decoded-ish value)
      .comments      list[Comment] (text, line, end_line)
      .stripped      source with comments blanked and string contents replaced by '_' (newlines kept),
                     same length / line numbers as the input -> safe for regex scans
      .errors        list[(line, message)] for unterminated strings/comments
  suppressed(lexed, line, tag) -> bool   True if `-- check:ignore` or `-- check:ignore(tag)` is on that line
                                         (or on the line just above, alone on its line).
"""

from __future__ import annotations

from dataclasses import dataclass, field

KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local",
    "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}
# Luau contextual keywords (`continue`, `type`, `export`, `typeof`) are lexed as names.

OPERATORS = [
    "...", "..=", "//=",
    "..", "==", "~=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "^=", "//", "->", "::",
    "+", "-", "*", "/", "%", "^", "#", "&", "~", "|", "<", ">", "=", "(", ")", "{", "}", "[", "]",
    ";", ":", ",", ".", "?",
]


@dataclass
class Tok:
    kind: str  # name | keyword | number | string | istring | op | eof
    value: str
    line: int
    col: int
    end_line: int = 0
    expr: bool = False  # True for if/then/elseif/else of an if-EXPRESSION (no `end`)

    def is_op(self, *ops: str) -> bool:
        return self.kind == "op" and self.value in ops

    def is_kw(self, *kws: str) -> bool:
        return self.kind == "keyword" and self.value in kws

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"Tok({self.kind},{self.value!r},{self.line})"


@dataclass
class Comment:
    text: str
    line: int
    end_line: int


@dataclass
class Lexed:
    tokens: list
    comments: list
    stripped: str
    errors: list = field(default_factory=list)
    ignore_lines: dict = field(default_factory=dict)  # line -> set of tags ("" = all)
    _lines: list = field(default_factory=list)

    def stripped_lines(self) -> list:
        if not self._lines:
            self._lines = self.stripped.split("\n")
        return self._lines


def _long_bracket_level(src: str, i: int) -> int:
    """At src[i] == '[': returns the level n of an opening long bracket [=*[ or -1."""
    j = i + 1
    n = 0
    while j < len(src) and src[j] == "=":
        n += 1
        j += 1
    if j < len(src) and src[j] == "[":
        return n
    return -1


def lex(src: str) -> Lexed:
    tokens: list[Tok] = []
    comments: list[Comment] = []
    errors: list = []
    out = list(src)  # stripped copy
    n = len(src)
    i = 0
    line = 1
    line_start = 0

    def blank(a: int, b: int, keep: str = " ") -> None:
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = keep

    def count_lines(a: int, b: int) -> None:
        nonlocal line, line_start
        k = src.find("\n", a, b)
        while k != -1:
            line += 1
            line_start = k + 1
            k = src.find("\n", k + 1, b)

    def lex_quoted(i0: int, quote: str) -> int:
        """Returns index after the closing quote (or end of line if unterminated)."""
        j = i0 + 1
        while j < n:
            c = src[j]
            if c == "\\":
                if j + 1 < n and src[j + 1] == "z":
                    j += 2
                    while j < n and src[j] in " \t\r\n":
                        j += 1
                    continue
                j += 2
                continue
            if c == quote:
                return j + 1
            if c == "\n":
                errors.append((line, "unterminated string"))
                return j
            j += 1
        errors.append((line, "unterminated string"))
        return n

    def decode_simple(raw: str) -> str:
        # Good enough for identifiers/keys: resolve the common escapes.
        if "\\" not in raw:
            return raw
        res = []
        k = 0
        while k < len(raw):
            c = raw[k]
            if c == "\\" and k + 1 < len(raw):
                nxt = raw[k + 1]
                res.append({"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'"}.get(nxt, nxt))
                k += 2
            else:
                res.append(c)
                k += 1
        return "".join(res)

    def lex_interp(i0: int) -> int:
        """Lexes `...{expr}...` starting at the backtick; expression tokens are appended."""
        j = i0 + 1
        seg_start = j
        while j < n:
            c = src[j]
            if c == "\\":
                j += 2
                continue
            if c == "`":
                blank(seg_start, j, "_")
                count_lines(seg_start, j)
                return j + 1
            if c == "{":
                blank(seg_start, j, "_")
                count_lines(seg_start, j)
                # lex code until the matching '}'
                j = lex_code(j + 1, stop_at_brace=True)
                seg_start = j
                continue
            j += 1
        errors.append((line, "unterminated interpolated string"))
        blank(seg_start, n, "_")
        return n

    def lex_code(start: int, stop_at_brace: bool = False) -> int:
        nonlocal line, line_start
        j = start
        brace = 0
        while j < n:
            c = src[j]
            if c == "\n":
                line += 1
                line_start = j + 1
                j += 1
                continue
            if c in " \t\r\f\v":
                j += 1
                continue
            col = j - line_start + 1
            # comments
            if c == "-" and src.startswith("--", j):
                k = j + 2
                if k < n and src[k] == "[":
                    lvl = _long_bracket_level(src, k)
                    if lvl >= 0:
                        close = "]" + "=" * lvl + "]"
                        e = src.find(close, k)
                        end = n if e == -1 else e + len(close)
                        if e == -1:
                            errors.append((line, "unterminated long comment"))
                        start_line = line
                        comments.append(Comment(src[j:end], start_line, start_line + src.count("\n", j, end)))
                        blank(j, end)
                        count_lines(j, end)
                        j = end
                        continue
                e = src.find("\n", j)
                end = n if e == -1 else e
                comments.append(Comment(src[j:end], line, line))
                blank(j, end)
                j = end
                continue
            # strings
            if c == '"' or c == "'":
                end = lex_quoted(j, c)
                raw = src[j + 1 : end - 1] if end <= n and end - 1 > j and src[end - 1] == c else src[j + 1 : end]
                tokens.append(Tok("string", decode_simple(raw), line, col, line + src.count("\n", j, end)))
                blank(j + 1, max(j + 1, end - 1), "_")
                count_lines(j, end)
                j = end
                continue
            if c == "[":
                lvl = _long_bracket_level(src, j)
                if lvl >= 0:
                    close = "]" + "=" * lvl + "]"
                    open_len = lvl + 2
                    e = src.find(close, j + open_len)
                    end = n if e == -1 else e + len(close)
                    if e == -1:
                        errors.append((line, "unterminated long string"))
                    body = src[j + open_len : (e if e != -1 else n)]
                    if body.startswith("\n"):
                        body = body[1:]
                    tokens.append(Tok("string", body, line, col, line + src.count("\n", j, end)))
                    blank(j + open_len, e if e != -1 else n, "_")
                    count_lines(j, end)
                    j = end
                    continue
            if c == "`":
                tokens.append(Tok("istring", "`", line, col))
                j = lex_interp(j)
                tokens.append(Tok("op", "`end", line, j - line_start))
                continue
            # numbers
            if c.isdigit() or (c == "." and j + 1 < n and src[j + 1].isdigit()):
                k = j
                if src.startswith(("0x", "0X"), j):
                    k += 2
                    while k < n and (src[k] in "0123456789abcdefABCDEF_"):
                        k += 1
                elif src.startswith(("0b", "0B"), j):
                    k += 2
                    while k < n and src[k] in "01_":
                        k += 1
                else:
                    while k < n and (src[k].isdigit() or src[k] in "._"):
                        if src[k] == "." and src.startswith("..", k):
                            break
                        k += 1
                    if k < n and src[k] in "eE":
                        k += 1
                        if k < n and src[k] in "+-":
                            k += 1
                        while k < n and src[k].isdigit():
                            k += 1
                tokens.append(Tok("number", src[j:k], line, col))
                j = k
                continue
            # names / keywords
            if c.isalpha() or c == "_":
                k = j + 1
                while k < n and (src[k].isalnum() or src[k] == "_"):
                    k += 1
                word = src[j:k]
                tokens.append(Tok("keyword" if word in KEYWORDS else "name", word, line, col))
                j = k
                continue
            # operators
            for op in OPERATORS:
                if src.startswith(op, j):
                    if stop_at_brace:
                        if op == "{":
                            brace += 1
                        elif op == "}":
                            if brace == 0:
                                return j + 1
                            brace -= 1
                    tokens.append(Tok("op", op, line, col))
                    j += len(op)
                    break
            else:
                errors.append((line, f"unexpected character {c!r}"))
                j += 1
        return j

    lex_code(0)
    tokens.append(Tok("eof", "", line, 1))
    classify_if_expressions(tokens)
    lexed = Lexed(tokens, comments, "".join(out), errors)
    # suppression comments: `-- check:ignore` or `-- check:ignore(tag1, tag2)`
    for cm in comments:
        text = cm.text
        idx = text.find("check:ignore")
        if idx == -1:
            continue
        rest = text[idx + len("check:ignore") :]
        tags = {""}
        if rest.startswith("("):
            close = rest.find(")")
            if close != -1:
                tags = {t.strip() for t in rest[1:close].split(",") if t.strip()}
        lexed.ignore_lines.setdefault(cm.line, set()).update(tags)
    return lexed


def suppressed(lexed: Lexed, line: int, tag: str) -> bool:
    for ln in (line, line - 1):
        tags = lexed.ignore_lines.get(ln)
        if tags and ("" in tags or tag in tags):
            if ln == line - 1:
                # only a comment that stands alone on the previous line applies to the next line
                if not _comment_only_line(lexed, ln):
                    continue
            return True
    return False


def _comment_only_line(lexed: Lexed, line: int) -> bool:
    lines = lexed.stripped_lines()
    if 0 < line <= len(lines):
        return lines[line - 1].strip() == ""
    return False


def matching(tokens: list, i: int) -> int:
    """tokens[i] is an opening bracket; returns the index of its matching closing bracket (or len-1)."""
    depth = 0
    for k in range(i, len(tokens)):
        t = tokens[k]
        if t.kind == "op":
            if t.value in ("(", "[", "{"):
                depth += 1
            elif t.value in (")", "]", "}"):
                depth -= 1
                if depth == 0:
                    return k
    return len(tokens) - 1


BLOCK_CLOSE = {"end", "until"}

# keywords after which an `if` starts an if-EXPRESSION (`local x = if a then b else c`)
_EXPR_KEYWORDS = {"return", "and", "or", "not", "in", "until", "while", "if", "elseif"}


def _expression_position(tokens: list, i: int) -> bool:
    if i == 0:
        return False
    p = tokens[i - 1]
    if p.kind == "op":
        # tokens that can END an expression or a type annotation (`): T?`, `Foo<T>`, `...`) precede statements
        return p.value not in (")", "]", "}", ";", "`end", "?", ">", "...")
    if p.kind == "keyword":
        return p.value in _EXPR_KEYWORDS
    return False


def classify_if_expressions(tokens: list) -> None:
    """Marks (Tok.expr = True) the if/then/elseif/else keywords that belong to if-expressions, which
    have no `end`. Every block counter must ignore them (see opens_block / closes_block)."""
    stack: list = []  # frames: [kind, state]; kind in ifexpr | ifstmt | block | repeat
    for i, t in enumerate(tokens):
        if t.kind != "keyword":
            continue
        v = t.value
        if v == "if":
            if _expression_position(tokens, i):
                t.expr = True
                stack.append(["ifexpr", "cond"])
            else:
                stack.append(["ifstmt", "cond"])
        elif v == "then":
            for f in reversed(stack):
                if f[0] in ("ifexpr", "ifstmt") and f[1] == "cond":
                    if f[0] == "ifexpr":
                        t.expr = True
                        f[1] = "branch"
                    else:
                        f[1] = "block"
                    break
        elif v == "elseif":
            if stack and stack[-1][0] == "ifexpr":
                t.expr = True
                stack[-1][1] = "cond"
            elif stack and stack[-1][0] == "ifstmt":
                stack[-1][1] = "cond"
        elif v == "else":
            if stack and stack[-1][0] == "ifexpr":
                t.expr = True
                stack.pop()  # the final expression follows; the frame is complete
            elif stack and stack[-1][0] == "ifstmt":
                stack[-1][1] = "else"
        elif v in ("function", "do"):
            stack.append(["block", None])
        elif v == "repeat":
            stack.append(["repeat", None])
        elif v in ("end", "until"):
            while stack and stack[-1][0] == "ifexpr":
                stack.pop()  # malformed input safety
            if stack:
                stack.pop()


def opens_block(t) -> bool:
    """function / do / repeat / if-STATEMENT (closed by end or until)."""
    return t.kind == "keyword" and (t.value in ("function", "do", "repeat") or (t.value == "if" and not t.expr))


def closes_block(t) -> bool:
    return t.kind == "keyword" and t.value in BLOCK_CLOSE


def skip_type(tokens: list, k: int) -> int:
    """tokens[k] starts a type (after `::` or `:`); returns the index just past a simple type:
    Name(.Name)*<...>? | {...} | (...) [-> type] | typeof(...), each optionally followed by `?`."""
    n = len(tokens)
    if k >= n:
        return k
    t = tokens[k]
    if t.kind == "name" and t.value == "typeof" and k + 1 < n and tokens[k + 1].is_op("("):
        k = matching(tokens, k + 1) + 1
    elif t.kind == "name" or t.is_kw("nil"):
        k += 1
        while k + 1 < n and tokens[k].is_op(".") and tokens[k + 1].kind == "name":
            k += 2
        if k < n and tokens[k].is_op("<"):
            depth = 0
            while k < n:
                if tokens[k].is_op("<"):
                    depth += 1
                elif tokens[k].is_op(">"):
                    depth -= 1
                    if depth == 0:
                        k += 1
                        break
                k += 1
    elif t.is_op("{", "("):
        k = matching(tokens, k) + 1
        if k < n and tokens[k].is_op("->"):
            return skip_type(tokens, k + 1)
    else:
        return k
    if k < n and tokens[k].is_op("?"):
        k += 1
    return k


def split_args(tokens: list, open_idx: int) -> list:
    """For a call whose '(' is at open_idx: list of (start, end_exclusive) token ranges of top-level args."""
    close = matching(tokens, open_idx)
    args = []
    depth = 0
    blocks = 0  # function bodies inside an argument contain their own commas
    start = open_idx + 1
    for k in range(open_idx + 1, close):
        t = tokens[k]
        if t.kind == "op":
            if t.value in ("(", "[", "{"):
                depth += 1
            elif t.value in (")", "]", "}"):
                depth -= 1
            elif t.value == "," and depth == 0 and blocks == 0:
                args.append((start, k))
                start = k + 1
        elif opens_block(t):
            blocks += 1
        elif closes_block(t):
            blocks -= 1
    if close > open_idx + 1:
        args.append((start, close))
    return args
