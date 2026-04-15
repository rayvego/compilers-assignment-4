%e  1019
%p  2807
%n  371
%k  284
%a  1213
%o  1117

O   [0-7]
D   [0-9]
NZ  [1-9]
L   [a-zA-Z_]
A   [a-zA-Z_0-9]
H   [a-fA-F0-9]
HP  (0[xX])
E   ([Ee][+-]?{D}+)
P   ([Pp][+-]?{D}+)
FS  (f|F|l|L)
IS  (((u|U)(l|L|ll|LL)?)|((l|L|ll|LL)(u|U)?))
CP  (u|U|L)
SP  (u8|u|U|L)
ES  (\\(['"\?\\abfnrtv]|[0-7]{1,3}|x[a-fA-F0-9]+))
WS  [ \t\v\f\r]

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "y.tab.h"

extern int yylineno;

static void comment(void);
%}

%%
"/*"                                    { comment(); }
"//".*                                  { /* consume //-comment */ }

"break"					{ return(BREAK); }
"case"					{ return(CASE); }
"char"					{ return(CHAR); }
"continue"				{ return(CONTINUE); }
"default"				{ return(DEFAULT); }
"do"					{ return(DO); }
"double"				{ return(DOUBLE); }
"else"					{ return(ELSE); }
"extern"				{ return(EXTERN); }
"float"					{ return(FLOAT); }
"for"					{ return(FOR); }
"if"					{ return(IF); }
"int"					{ return(INT); }
"long"					{ return(LONG); }
"return"				{ return(RETURN); }
"short"					{ return(SHORT); }
"sizeof"				{ yylval.name = strdup("sizeof"); return(SIZEOF); }
"struct"				{ return(STRUCT); }
"switch"				{ return(SWITCH); }
"void"					{ return(VOID); }
"while"					{ return(WHILE); }

{L}{A}*					{ yylval.name = strdup(yytext); return IDENTIFIER; }

{HP}{H}+{IS}?				{ yylval.name = strdup(yytext); return I_CONSTANT; }
{NZ}{D}*{IS}?				{ yylval.name = strdup(yytext); return I_CONSTANT; }
"0"{O}*{IS}?				{ yylval.name = strdup(yytext); return I_CONSTANT; }
{CP}?"'"([^'\\\n]|{ES})+"'"		{ yylval.name = strdup(yytext); return I_CONSTANT; }

{D}+{E}{FS}?				{ yylval.name = strdup(yytext); return F_CONSTANT; }
{D}*"."{D}+{E}?{FS}?			{ yylval.name = strdup(yytext); return F_CONSTANT; }
{D}+"."{E}?{FS}?			{ yylval.name = strdup(yytext); return F_CONSTANT; }
{HP}{H}+{P}{FS}?			{ yylval.name = strdup(yytext); return F_CONSTANT; }
{HP}{H}*"."{H}+{P}{FS}?			{ yylval.name = strdup(yytext); return F_CONSTANT; }
{HP}{H}+"."{P}{FS}?			{ yylval.name = strdup(yytext); return F_CONSTANT; }

({SP}?\"([^"\\\n]|{ES})*\"{WS}*)+	{ yylval.name = strdup(yytext); return STRING_LITERAL; }

"<=>"					{ return TH_OP; }
"++"					{ return INC_OP; }
"--"					{ return DEC_OP; }
"->"					{ return PTR_OP; }
"&&"					{ return AND_OP; }
"||"					{ return OR_OP; }
"<="					{ return LE_OP; }
">="					{ return GE_OP; }
"=="					{ return EQ_OP; }
"!="					{ return NE_OP; }
";"					{ return ';'; }
("{"|"<%")				{ return '{'; }
("}"|"%>")				{ return '}'; }
","					{ return ','; }
":"					{ return ':'; }
"="					{ return '='; }
"("					{ return '('; }
")"					{ return ')'; }
("["|"<:")				{ return '['; }
("]"|":>")				{ return ']'; }
"."					{ return '.'; }
"&"					{ return '&'; }
"!"					{ return '!'; }
"~"					{ return '~'; }
"-"					{ return '-'; }
"+"					{ return '+'; }
"*"					{ return '*'; }
"/"					{ return '/'; }
"%"					{ return '%'; }
"<"					{ return '<'; }
">"					{ return '>'; }
"^"					{ return '^'; }
"|"					{ return '|'; }

\n					{ yylineno++; }
[ \t\v\f\r]+				{ /* whitespace separates tokens */ }
.					{ /* discard bad characters */ }

%%

int yywrap(void)        /* called at end of input */
{
    return 1;           /* terminate now */
}

static void comment(void)
{
    int c;

    while ((c = input()) != 0)
    {
        if (c == '\n') yylineno++;
        if (c == '*')
        {
            while ((c = input()) == '*')
                ;

            if (c == '\n') yylineno++;

            if (c == '/')
                return;

            if (c == 0)
                break;
        }
    }

    fprintf(stderr, "[Lexer Error] Ill-formed comment (starting before line %d)\n", yylineno);
    exit(1);
}