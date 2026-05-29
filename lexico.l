%{
#include <string>
#include <stdio.h>

struct atributos {
    std::string label;
    std::string traducao;
    std::string tipo;
};

#define YYSTYPE atributos

#include "y.tab.h"

int linha = 1; 
%}

%option noyywrap

DIGITO      [0-9]
LETRA       [a-zA-Z_]
NUM_INT     {DIGITO}+
NUM_FLOAT   {DIGITO}+"."{DIGITO}+
ID          {LETRA}({LETRA}|{DIGITO})*

%%

"\n"        { linha++; } 
[ \t]+      { }

"int"       { return TK_TIPO_INT; } 
"float"     { return TK_TIPO_FLOAT; } 
"char"      { return TK_TIPO_CHAR; }
"bool"      { return TK_TIPO_BOOL; }

"true"      { return TK_TRUE; } 
"false"     { return TK_FALSE; }
  
"print"     { return TK_PRINT; }
"read"      { return TK_READ; }

"if"        { return TK_IF; }
"else"      { return TK_ELSE; }
"while"     { return TK_WHILE; }
"for"       { return TK_FOR; }
"do"        { return TK_DO; }

"break"     { return TK_BREAK; }
"continue"  { return TK_CONTINUE; }

\'.\'       { yylval.label = yytext; yylval.tipo = "char"; return TK_NUM; } 
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
"{"         { return '{'; }
"}"         { return '}'; }
":"         { return ':'; }
";"         { return ';'; }

.           { fprintf(stderr, "Caractere nao reconhecido na linha %d: %s\n", linha, yytext); }

%%