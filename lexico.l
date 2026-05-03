%{
#include <string>
#include <stdio.h>
#include "y.tab.h"

int linha = 1;
%}

%option noyywrap

ESPACO      [ \t]
DIGITO      [0-9]
LETRA       [a-zA-Z_]

DELIM       {ESPACO}+
NUM_INT     {DIGITO}+
NUM_FLOAT   {DIGITO}+"."{DIGITO}+
ID          {LETRA}({LETRA}|{DIGITO})*

%%

"\n"        { linha++; }
{DELIM}     { }

"int"       { return TK_TIPO_INT; }
"float"     { return TK_TIPO_FLOAT; }
"char"      { return TK_TIPO_CHAR; }
"bool"      { return TK_TIPO_BOOL; }
"true"      { yylval.label = "1"; yylval.tipo = "bool"; return TK_TRUE; }
"false"     { yylval.label = "0"; yylval.tipo = "bool"; return TK_FALSE; }

{NUM_FLOAT} { yylval.label = yytext; yylval.tipo = "float"; return TK_NUM; }
{NUM_INT}   { yylval.label = yytext; yylval.tipo = "int";   return TK_NUM; }
{ID}        { yylval.label = yytext; return TK_ID; }

"+"         { return '+'; }
"-"         { return '-'; }
"*"         { return '*'; }
"/"         { return '/'; }

"&&"        { return TK_E; }
"||"        { return TK_OU; }
"!"         { return TK_NAO; }

"=="        { return TK_IGUAL; }
"!="        { return TK_DIFERENTE; }
"<="        { return TK_MENOR_IGUAL; }
">="        { return TK_MAIOR_IGUAL; }
"<"         { return '<'; }
">"         { return '>'; }

"="         { return TK_ATRIB; }
"("         { return '('; }
")"         { return ')'; }
":"         { return ':'; }

.           { fprintf(stderr, "Caractere nao reconhecido na linha %d: %s\n", linha, yytext); }

%%