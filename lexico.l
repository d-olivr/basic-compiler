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
[ \t\r\xa0]+    { /* ignora espaços, tabs, quebras do windows e espaços fantasmas */ }

"int"       { return TK_TIPO_INT; } 
"float"     { return TK_TIPO_FLOAT; } 
"char"      { return TK_TIPO_CHAR; }
"string"    { return TK_TIPO_STRING; }
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

"switch"    { return TK_SWITCH; }
"case"      { return TK_CASE; }
"default"   { return TK_DEFAULT; }

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
\"[^\"\n]*\"  {
    int len = strlen(yytext) - 2; // -2 para descontar as aspas
    if (len > 4500) {
        fprintf(stderr, "Erro lexico na linha %d: string literal excede 4500 caracteres (%d)\n", linha, len);
        exit(1);
    }
    yylval.label = yytext;
    yylval.tipo = "string";
    return TK_STR_LITERAL;
}

.           { fprintf(stderr, "Caractere nao reconhecido na linha %d: %s\n", linha, yytext); }

%%