# CS327 Assignment 4: Intermediate Code Generation (3AC Quadruples)

## Project Overview

This project extends the YAPL parser (Assignment 3) to generate Three Address Code (3AC) in quadruple format using Syntax Directed Translation. The compiler reads a YAPL (C-like) source file and outputs the intermediate representation as a table of quadruples.

**Group:** Group 17: Mohit Kamlesh Panchal (23110208)

---

## How to Build

```bash
make
```

This runs `bison`, `lex`, and `gcc` to produce the `yapl4` binary.

To clean build artifacts:

```bash
make clean
```

---

## How to Run

```bash
./yapl4 <source_file.yapl>
```

The program reads the source file, echoes it under `===== Source Code =====`, then prints the 3AC quadruple table under `===== Intermediate Code (3AC Quadruples) =====`.

---

## IR Design

### Quad Struct

Each quadruple has four fields:

| Field    | Type     | Description                          |
|----------|----------|--------------------------------------|
| `op`     | `char[]` | Operator (e.g., `+`, `-`, `*`, `if==0`, `goto`) |
| `arg1`   | `char[]` | First operand or condition variable  |
| `arg2`   | `char[]` | Second operand (empty shown as `-`)  |
| `result` | `char[]` | Destination variable or jump target  |

A global array `Quad quads[10000]` holds up to 10,000 quadruples. The counter `quad_count` tracks the next free slot.

### Temp Variables

- `new_temp()` returns `t1`, `t2`, `t3`, ... in sequence.
- Temporaries are fresh each run (reset via `reset_ir()`).

### Labels

- `new_label()` returns `L1`, `L2`, ... (available but unused in final design).
- Jump targets use **1-based quad indices** in the `result` field instead of symbolic labels.

### Backpatching Strategy

- **Index-based backpatching**: When a conditional or unconditional jump is emitted before its target is known, the `result` field is left as `NULL`. After the target quad index is known, `backpatch(qi, target)` writes the 1-based index into the quad's `result` field.
- **Value stack** (`PUSH`/`POP`): A LIFO stack passes quad indices between mid-rule and end-of-rule actions in yacc. This avoids anonymous non-terminals (M, N, J markers) that cause reduce/reduce conflicts.
- **`move_quads_to_end()`**: For `for` loops with an increment expression, the increment quads are parsed between the condition and `)`. They are relocated after the loop body so the execution order becomes: `[init][cond][if==0][body][incr][goto→cond]`.

---

## Construct → Quadruples Translation

| Construct                 | Quads Emitted                                                                 |
|---------------------------|-------------------------------------------------------------------------------|
| Arithmetic `a + b`        | `(+, a, b, t1)`                                                              |
| Unary minus `-a`          | `(minus, a, _, t1)`                                                           |
| Unary `!`, `~`            | `(!, a, _, t1)`, `(~, a, _, t1)`                                              |
| Assignment `x = expr`     | `(=, expr, _, x)`                                                              |
| If (no else)              | `[cond][if==0→Lend][body] Lend:`                                               |
| If-else                   | `[cond][if==0→Lelse][true_body][goto→Lend] Lelse:[false_body] Lend:`           |
| While                     | `Lcond:[cond][if==0→Lend][body][goto→Lcond] Lend:`                             |
| Do-while                  | `Lstart:[body][cond][if!=0→Lstart]`                                            |
| For (with incr)           | `[init][cond][if==0→Lend][body][incr][goto→Lcond] Lend:` (incr moved after body) |

---

## Output Format

1. Source code echoed under `===== Source Code =====`
2. IR table with header row: `| Index | op | arg1 | arg2 | result |`
3. Each quad printed as a row; empty `arg2` shown as `-`
4. `Total quadruples: N` printed after the table

---

## Error Handling

- `emit()` checks for NULL `op` and quad array overflow, prints an `[IR Error]` message and skips insertion.
- `yyerror()` prints a `[Syntax Error]` message with line number and offending token, then exits cleanly (no segfault).
- Invalid input programs are caught at the parser level and produce a clear error message.

---

## Example Programs

| #   | File          | Description                                              |
|-----|---------------|----------------------------------------------------------|
| 01  | `ex01.yapl`   | Simple arithmetic: `a = b * -c + b * -c` (spec example)  |
| 02  | `ex02.yapl`   | Nested arithmetic with multiple assignments               |
| 03  | `ex03.yapl`   | If statement (no else)                                    |
| 04  | `ex04.yapl`   | If-else statement                                         |
| 05  | `ex05.yapl`   | Nested if-else (2 levels deep)                            |
| 06  | `ex06.yapl`   | While loop                                                |
| 07  | `ex07.yapl`   | For loop with increment                                   |
| 08  | `ex08.yapl`   | Do-while loop                                             |
| 09  | `ex09.yapl`   | Combined if + while inside a function                      |
| 10  | `ex10.yapl`   | Larger program: for + if-else + multiple expressions       |

Each source file has a corresponding `.out` file with the full compiler output.

### Error Test Cases

| #   | File          | Description                                              |
|-----|---------------|----------------------------------------------------------|
| E1  | `err01.yapl`  | Missing operand: `x = 5 + ;`                             |
| E2  | `err02.yapl`  | Mismatched parentheses: `int main( { ... }`              |

Both produce graceful `[Syntax Error]` messages with line numbers.

---

## End-to-End Pipeline

```
Source (.yapl) → Lex (yapl.l) → Yacc/SDT (yapl.y) → Quad Array → Tabular Output
```

1. **Lex** tokenizes the source into terminals with semantic values (`yylval.name = strdup(yytext)`).
2. **Yacc** parses using C11 grammar rules; semantic actions emit quads via `emit()` and backpatch jump targets as soon as they are known.
3. **Quad array** accumulates all 3AC quadruples during parsing.
4. **Tabular output** is printed by `print_quads()` after parsing completes.