%{
/* CS327 Assignment 4: Intermediate Code Generation (3AC Quadruples) */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int yylex(void);
void yyerror(const char *s);

extern char *yytext;
extern int yylineno;

/* IR Infrastructure */

#define MAX_QUADS 10000

typedef struct {
    char op[32];
    char arg1[64];
    char arg2[64];
    char result[64];
} Quad;

Quad quads[MAX_QUADS];
int quad_count = 0;

static int temp_counter = 0;
static int label_counter = 0;

static char *new_temp(void)
{
    char buf[16];
    snprintf(buf, sizeof(buf), "t%d", ++temp_counter);
    return strdup(buf);
}

static char *new_label(void)
{
    char buf[16];
    snprintf(buf, sizeof(buf), "L%d", ++label_counter);
    return strdup(buf);
}

static void emit(const char *op, const char *arg1, const char *arg2,
                 const char *result)
{
    if (quad_count >= MAX_QUADS) {
        fprintf(stderr, "[IR Error] Quad array overflow (max %d)\n", MAX_QUADS);
        return;
    }
    if (!op) {
        fprintf(stderr, "[IR Error] NULL operator at quad %d\n", quad_count);
        return;
    }
    strncpy(quads[quad_count].op, op, 31);
    quads[quad_count].op[31] = '\0';
    strncpy(quads[quad_count].arg1, arg1 ? arg1 : "", 63);
    quads[quad_count].arg1[63] = '\0';
    strncpy(quads[quad_count].arg2, arg2 ? arg2 : "", 63);
    quads[quad_count].arg2[63] = '\0';
    strncpy(quads[quad_count].result, result ? result : "", 63);
    quads[quad_count].result[63] = '\0';
    quad_count++;
}

static void reset_ir(void)
{
    quad_count = 0;
    temp_counter = 0;
    label_counter = 0;
}

/* Source echo buffer */

static char *source_buf = NULL;
static size_t source_buf_sz = 0;

static char *read_entire_file(const char *path)
{
    FILE *fp = fopen(path, "r");
    if (!fp) return NULL;
    fseek(fp, 0, SEEK_END);
    long sz = ftell(fp);
    rewind(fp);
    char *buf = malloc(sz + 1);
    if (!buf) { fclose(fp); return NULL; }
    fread(buf, 1, sz, fp);
    buf[sz] = '\0';
    fclose(fp);
    return buf;
}

static void print_quads(void)
{
    printf("\n+-------+------------+------------+------------+------------+\n");
    printf("| %-5s | %-10s | %-10s | %-10s | %-10s |\n",
           "Index", "op", "arg1", "arg2", "result");
    printf("+-------+------------+------------+------------+------------+\n");
    for (int i = 0; i < quad_count; i++) {
        printf("| %-5d | %-10s | %-10s | %-10s | %-10s |\n",
               i + 1,
               quads[i].op,
               quads[i].arg1,
               quads[i].arg2[0] ? quads[i].arg2 : "-",
               quads[i].result);
    }
    printf("+-------+------------+------------+------------+------------+\n");
    printf("Total quadruples: %d\n", quad_count);
}

/* Backpatching helper: patch the 'result' field of quad at index 'qi' to hold the string representation of target quad index 'target'. (Quad indices are 0-based internally; displayed 1-based.) */
static void backpatch(int qi, int target)
{
    snprintf(quads[qi].result, sizeof(quads[qi].result), "%d", target + 1);
}

/* Move a range of quads from [src_start, src_end) to the end of the array. Used to relocate for-loop increment quads after the body. Returns the number of quads moved. */
static int move_quads_to_end(int src_start, int src_end)
{
    int count = src_end - src_start;
    if (count <= 0) return 0;

    Quad *saved = malloc(sizeof(Quad) * count);
    memcpy(saved, &quads[src_start], sizeof(Quad) * count);

    memmove(&quads[src_start], &quads[src_end],
            sizeof(Quad) * (quad_count - src_end));

    memcpy(&quads[quad_count - count], saved, sizeof(Quad) * count);
    free(saved);

    return count;
}

/* Value stack for passing data between mid-rule and end-of-rule actions. Used instead of named ε-productions (M, N, J) to avoid R/R conflicts. PUSH captures quad indices or other values; POP retrieves them in LIFO order, which naturally matches nested control flow. */
#define MAX_NEST 100
static int val_stack[MAX_NEST];
static int val_top = 0;

#define PUSH(v) (val_stack[val_top++] = (v))
#define POP()   (val_stack[--val_top])

%}

%union {
    char *name;
    int   val;
}

%token <name> IDENTIFIER I_CONSTANT F_CONSTANT STRING_LITERAL FUNC_NAME

%token <name> SIZEOF
%token  PTR_OP INC_OP DEC_OP LE_OP GE_OP EQ_OP NE_OP TH_OP
%token  AND_OP OR_OP
%token  TYPEDEF_NAME ENUMERATION_CONSTANT
%token  EXTERN
%token  CHAR SHORT INT LONG FLOAT DOUBLE VOID
%token  STRUCT
%token  CASE DEFAULT IF ELSE SWITCH WHILE DO FOR CONTINUE BREAK RETURN

%type <name> primary_expression
%type <name> constant
%type <name> string
%type <name> postfix_expression
%type <name> argument_expression_list
%type <name> unary_expression
%type <name> unary_operator
%type <name> cast_expression
%type <name> multiplicative_expression
%type <name> additive_expression
%type <name> shift_expression
%type <name> relational_expression
%type <name> equality_expression
%type <name> and_expression
%type <name> exclusive_or_expression
%type <name> inclusive_or_expression
%type <name> logical_and_expression
%type <name> logical_or_expression
%type <name> conditional_expression
%type <name> assignment_expression
%type <name> expression
%type <name> constant_expression
%type <name> initializer
%type <name> expression_statement
%type <val>  if_cond

/* Dangling-else precedence fix */
%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE

%start translation_unit

%%

/* Expressions */

primary_expression
    : IDENTIFIER              { $$ = $1; }
    | constant                { $$ = $1; }
    | string                  { $$ = $1; }
    | '(' expression ')'      { $$ = $2; }
    ;

constant
    : I_CONSTANT             { $$ = $1; }
    | F_CONSTANT              { $$ = $1; }
    ;

string
    : STRING_LITERAL          { $$ = $1; }
    | FUNC_NAME               { $$ = $1; }
    ;

postfix_expression
    : primary_expression                                          { $$ = $1; }
    | postfix_expression '[' expression ']'                       { $$ = $1; }
    | postfix_expression '(' ')'                                  { $$ = $1; }
    | postfix_expression '(' argument_expression_list ')'          { $$ = $1; }
    | postfix_expression '.' IDENTIFIER                           { $$ = $1; }
    | postfix_expression PTR_OP IDENTIFIER                        { $$ = $1; }
    | postfix_expression INC_OP                                   { $$ = $1; }
    | postfix_expression DEC_OP                                   { $$ = $1; }
    ;

argument_expression_list
    : assignment_expression                                       { $$ = $1; }
    | argument_expression_list ',' assignment_expression          { $$ = $1; }
    ;

unary_expression
    : postfix_expression                                          { $$ = $1; }
    | INC_OP unary_expression               { $$ = $2; /* ++x */ }
    | DEC_OP unary_expression               { $$ = $2; /* --x */ }
    | unary_operator cast_expression
        {
            if (strcmp($1, "-") == 0) {
                $$ = new_temp();
                emit("minus", $2, NULL, $$);
            } else if (strcmp($1, "+") == 0) {
                /* unary plus is a no-op */
                $$ = $2;
            } else if (strcmp($1, "!") == 0) {
                $$ = new_temp();
                emit("!", $2, NULL, $$);
            } else if (strcmp($1, "~") == 0) {
                $$ = new_temp();
                emit("~", $2, NULL, $$);
            } else {
                $$ = $2;
            }
            free($1);
        }
    | SIZEOF unary_expression              { $$ = $2; }
    | SIZEOF '(' type_name ')'             { $$ = strdup("0"); }
    ;

unary_operator
    : '&'   { $$ = strdup("&"); }
    | '*'   { $$ = strdup("*"); }
    | '+'   { $$ = strdup("+"); }
    | '-'   { $$ = strdup("-"); }
    | '~'   { $$ = strdup("~"); }
    | '!'   { $$ = strdup("!"); }
    ;

cast_expression
    : unary_expression                                            { $$ = $1; }
    | '(' type_name ')' cast_expression                           { $$ = $4; }
    ;

multiplicative_expression
    : cast_expression                                              { $$ = $1; }
    | multiplicative_expression '*' cast_expression
        { $$ = new_temp(); emit("*", $1, $3, $$); }
    | multiplicative_expression '/' cast_expression
        { $$ = new_temp(); emit("/", $1, $3, $$); }
    | multiplicative_expression '%' cast_expression
        { $$ = new_temp(); emit("%", $1, $3, $$); }
    ;

additive_expression
    : multiplicative_expression                                    { $$ = $1; }
    | additive_expression '+' multiplicative_expression
        { $$ = new_temp(); emit("+", $1, $3, $$); }
    | additive_expression '-' multiplicative_expression
        { $$ = new_temp(); emit("-", $1, $3, $$); }
    ;

shift_expression
    : additive_expression                                          { $$ = $1; }
    ;

relational_expression
    : shift_expression                                             { $$ = $1; }
    | relational_expression '<' shift_expression
        { $$ = new_temp(); emit("<", $1, $3, $$); }
    | relational_expression '>' shift_expression
        { $$ = new_temp(); emit(">", $1, $3, $$); }
    | relational_expression LE_OP shift_expression
        { $$ = new_temp(); emit("<=", $1, $3, $$); }
    | relational_expression GE_OP shift_expression
        { $$ = new_temp(); emit(">=", $1, $3, $$); }
    | relational_expression TH_OP shift_expression
        { $$ = new_temp(); emit("<=>", $1, $3, $$); }
    ;

equality_expression
    : relational_expression                                        { $$ = $1; }
    | equality_expression EQ_OP relational_expression
        { $$ = new_temp(); emit("==", $1, $3, $$); }
    | equality_expression NE_OP relational_expression
        { $$ = new_temp(); emit("!=", $1, $3, $$); }
    ;

and_expression
    : equality_expression                                          { $$ = $1; }
    | and_expression '&' equality_expression
        { $$ = new_temp(); emit("&", $1, $3, $$); }
    ;

exclusive_or_expression
    : and_expression                                               { $$ = $1; }
    | exclusive_or_expression '^' and_expression
        { $$ = new_temp(); emit("^", $1, $3, $$); }
    ;

inclusive_or_expression
    : exclusive_or_expression                                      { $$ = $1; }
    | inclusive_or_expression '|' exclusive_or_expression
        { $$ = new_temp(); emit("|", $1, $3, $$); }
    ;

logical_and_expression
    : inclusive_or_expression                                     { $$ = $1; }
    | logical_and_expression AND_OP inclusive_or_expression
        { $$ = new_temp(); emit("&&", $1, $3, $$); }
    ;

logical_or_expression
    : logical_and_expression                                       { $$ = $1; }
    | logical_or_expression OR_OP logical_and_expression
        { $$ = new_temp(); emit("||", $1, $3, $$); }
    ;

conditional_expression
    : logical_or_expression                                        { $$ = $1; }
    ;

assignment_expression
    : conditional_expression                                       { $$ = $1; }
    | unary_expression '=' assignment_expression
        { emit("=", $3, NULL, $1); $$ = $1; }
    ;

expression
    : assignment_expression                                        { $$ = $1; }
    | expression ',' assignment_expression                        { $$ = $3; }
    ;

constant_expression
    : conditional_expression                                      { $$ = $1; }
    ;

/* Declarations */

declaration
    : declaration_specifiers ';'
    | declaration_specifiers init_declarator_list ';'
    ;

declaration_specifiers
    : storage_class_specifier declaration_specifiers
    | storage_class_specifier
    | type_specifier declaration_specifiers
    | type_specifier
    ;

init_declarator_list
    : init_declarator
    | init_declarator_list ',' init_declarator
    ;

init_declarator
    : declarator '=' initializer
    | declarator
    ;

storage_class_specifier
    : EXTERN
    ;

type_specifier
    : VOID
    | CHAR
    | SHORT
    | INT
    | LONG
    | FLOAT
    | DOUBLE
    | struct_or_union_specifier
    ;

struct_or_union_specifier
    : struct_or_union '{' struct_declaration_list '}'
    | struct_or_union IDENTIFIER '{' struct_declaration_list '}'
    | struct_or_union IDENTIFIER
    ;

struct_or_union
    : STRUCT
    ;

struct_declaration_list
    : struct_declaration
    | struct_declaration_list struct_declaration
    ;

struct_declaration
    : specifier_qualifier_list ';'
    | specifier_qualifier_list struct_declarator_list ';'
    ;

specifier_qualifier_list
    : type_specifier specifier_qualifier_list
    | type_specifier
    ;

struct_declarator_list
    : struct_declarator
    | struct_declarator_list ',' struct_declarator
    ;

struct_declarator
    : ':' constant_expression
    | declarator ':' constant_expression
    | declarator
    ;

/* Conflict 1 fix: pointer counter action moved to end of rule */
declarator
    : pointer direct_declarator
    | direct_declarator
    ;

direct_declarator
    : IDENTIFIER
    | '(' declarator ')'
    | direct_declarator '[' ']'
    | direct_declarator '[' '*' ']'
    | direct_declarator '[' assignment_expression ']'
    | direct_declarator '(' parameter_type_list ')'
    | direct_declarator '(' ')'
    | direct_declarator '(' identifier_list ')'
    ;

pointer
    : '*' pointer
    | '*'
    ;

parameter_type_list
    : parameter_list
    ;

parameter_list
    : parameter_declaration
    | parameter_list ',' parameter_declaration
    ;

parameter_declaration
    : declaration_specifiers declarator
    | declaration_specifiers abstract_declarator
    | declaration_specifiers
    ;

identifier_list
    : IDENTIFIER
    | identifier_list ',' IDENTIFIER
    ;

type_name
    : specifier_qualifier_list abstract_declarator
    | specifier_qualifier_list
    ;

abstract_declarator
    : pointer direct_abstract_declarator
    | pointer
    | direct_abstract_declarator
    ;

direct_abstract_declarator
    : '(' abstract_declarator ')'
    | '[' ']'
    | '[' '*' ']'
    | '[' assignment_expression ']'
    | direct_abstract_declarator '[' ']'
    | direct_abstract_declarator '[' '*' ']'
    | direct_abstract_declarator '[' assignment_expression ']'
    | '(' ')'
    | '(' parameter_type_list ')'
    | direct_abstract_declarator '(' ')'
    | direct_abstract_declarator '(' parameter_type_list ')'
    ;

initializer
    : '{' initializer_list '}'               { $$ = strdup("{}"); }
    | '{' initializer_list ',' '}'            { $$ = strdup("{}"); }
    | assignment_expression                   { $$ = $1; }
    ;

initializer_list
    : designation initializer
    | initializer
    | initializer_list ',' designation initializer
    | initializer_list ',' initializer
    ;

designation
    : designator_list '='
    ;

designator_list
    : designator
    | designator_list designator
    ;

designator
    : '[' constant_expression ']'
    | '.' IDENTIFIER
    ;

/* Statements */

statement
    : labeled_statement
    | compound_statement
    | expression_statement
    | selection_statement
    | iteration_statement
    | jump_statement
    ;

labeled_statement
    : IDENTIFIER ':' statement
    | CASE constant_expression ':' statement
    | DEFAULT ':' statement
    ;

compound_statement
    : '{' '}'
    | '{' block_item_list '}'
    ;

block_item_list
    : block_item
    | block_item_list block_item
    ;

block_item
    : declaration
    | statement
    ;

expression_statement
    : ';'                      { $$ = NULL; }
    | expression ';'           { $$ = $1; }
    ;

if_cond
    : IF '(' expression ')'
        { emit("if==0", $3, "0", NULL); $$ = quad_count - 1; }
    ;

for_init_e
    : FOR '(' expression_statement
        { PUSH(quad_count); }
    ;

for_init_d
    : FOR '(' declaration
        { PUSH(quad_count); }
    ;

selection_statement
    /* if (e) S */
    : if_cond statement %prec LOWER_THAN_ELSE
        { backpatch($1, quad_count); }

    /* if (e) S1 else S2
       Quads: [cond][if==0->Lelse][S1][goto->Lend] Lelse:[S2] Lend: */
    | if_cond statement ELSE { emit("goto", NULL, NULL, NULL); PUSH(quad_count - 1); } statement
        {
            int gi = POP();
            backpatch($1, gi + 1);
            backpatch(gi, quad_count);
        }

    | SWITCH '(' expression ')' statement
        { /* SWITCH not implemented */ }
    ;

iteration_statement
    /*
     * while (e) S
     * Quads: Lcond:[cond][if==0->Lend][body][goto->Lcond] Lend:
     */
    : WHILE '(' { PUSH(quad_count); } expression ')'
      { emit("if==0", $4, "0", NULL); PUSH(quad_count - 1); }
      statement
        {
            int ji = POP();
            int ls = POP();
            char target[16];
            snprintf(target, sizeof(target), "%d", ls + 1);
            emit("goto", target, NULL, NULL);
            backpatch(ji, quad_count);
        }

    /*
     * do S while (e)
     * Quads: Lstart:[body][cond][if!=0->Lstart]
     */
    | DO { PUSH(quad_count); } statement WHILE '(' expression ')' ';'
        {
            int ls = POP();
            char target[16];
            snprintf(target, sizeof(target), "%d", ls + 1);
            emit("if!=0", $6, "0", target);
        }

    /*
     * for (init_expr; cond_expr; ) body
     * Quads: [init] Lcond:[cond][if==0->Lend][body][goto->Lcond] Lend:
     */
    | for_init_e expression_statement ')'
      { if ($2) { emit("if==0", $2, "0", NULL); PUSH(quad_count - 1); }
        else     { PUSH(-1); } }
      statement
        {
            int ji         = POP();
            int cond_start = POP();
            if (ji >= 0) {
                char target[16];
                snprintf(target, sizeof(target), "%d", cond_start + 1);
                emit("goto", target, NULL, NULL);
                backpatch(ji, quad_count);
            }
        }

    /*
     * for (init_expr; cond_expr; incr_expr) body
     * Parsed order:  [init][cond][incr][if==0][body]
     * Desired order: [init][cond][if==0][body][incr][goto->Lcond]
     */
    | for_init_e expression_statement { PUSH(quad_count); } expression ')'
      { if ($2) { emit("if==0", $2, "0", NULL); PUSH(quad_count - 1); }
        else     { PUSH(-1); } }
      statement
        {
            int ji         = POP();
            int incr_start = POP();
            int cond_start = POP();
            if (ji >= 0) {
                move_quads_to_end(incr_start, ji);
                char target[16];
                snprintf(target, sizeof(target), "%d", cond_start + 1);
                emit("goto", target, NULL, NULL);
                backpatch(incr_start, quad_count);
            }
        }

    /* for (decl; cond_expr; ) body */
    | for_init_d expression_statement ')'
      { if ($2) { emit("if==0", $2, "0", NULL); PUSH(quad_count - 1); }
        else     { PUSH(-1); } }
      statement
        {
            int ji         = POP();
            int cond_start = POP();
            if (ji >= 0) {
                char target[16];
                snprintf(target, sizeof(target), "%d", cond_start + 1);
                emit("goto", target, NULL, NULL);
                backpatch(ji, quad_count);
            }
        }

    /* for (decl; cond_expr; incr_expr) body */
    | for_init_d expression_statement { PUSH(quad_count); } expression ')'
      { if ($2) { emit("if==0", $2, "0", NULL); PUSH(quad_count - 1); }
        else     { PUSH(-1); } }
      statement
        {
            int ji         = POP();
            int incr_start = POP();
            int cond_start = POP();
            if (ji >= 0) {
                move_quads_to_end(incr_start, ji);
                char target[16];
                snprintf(target, sizeof(target), "%d", cond_start + 1);
                emit("goto", target, NULL, NULL);
                backpatch(incr_start, quad_count);
            }
        }
    ;

jump_statement
    : CONTINUE ';'
    | BREAK ';'
    | RETURN ';'
    | RETURN expression ';'
    ;

/* Top-level */

translation_unit
    : external_declaration
    | translation_unit external_declaration
    ;

external_declaration
    : function_definition
    | declaration
    ;

function_definition
    : declaration_specifiers declarator declaration_list compound_statement
    | declaration_specifiers declarator compound_statement
    ;

declaration_list
    : declaration
    | declaration_list declaration
    ;

%%

/* Epilogue */

void yyerror(const char *s)
{
    fflush(stdout);
    fprintf(stderr, "[Syntax Error] at line %d: %s (near token '%s')\n",
            yylineno, s, yytext ? yytext : "?");
    exit(1);
}

int main(int argc, char **argv)
{
    extern FILE *yyin;

    if (argc < 2) {
        fprintf(stderr, "Usage: %s <source_file>\n", argv[0]);
        return 1;
    }

    const char *src = argv[1];

    source_buf = read_entire_file(src);
    if (!source_buf) {
        fprintf(stderr, "[Error] Cannot open file \"%s\"\n", src);
        return 1;
    }

    printf("===== Source Code =====\n");
    printf("%s", source_buf);
    printf("\n===== Intermediate Code (3AC Quadruples) =====\n");

    reset_ir();

    yyin = fopen(src, "r");
    if (!yyin) {
        fprintf(stderr, "[Error] Cannot re-open file \"%s\" for parsing\n", src);
        free(source_buf);
        return 1;
    }

    do { yyparse(); } while (!feof(yyin));

    print_quads();

    free(source_buf);
    fclose(yyin);
    return 0;
}