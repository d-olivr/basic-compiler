%{
#include <string>
#include <vector>
#include <stdio.h>

struct atributos {
    std::string label;
    std::string traducao;
    std::string tipo;
    std::vector<std::string> listaLabels;
    std::vector<std::string> listaTipos;
};

#define YYSTYPE atributos

#include "y.tab.h"

int linha = 1;
extern bool houveErro; // declarada/definida em sintatico.y, usada para sinalizar erro lexico
%}

%option noyywrap

DIGITO      [0-9]
LETRA       [a-zA-Z_]
NUM_INT     {DIGITO}+
NUM_FLOAT   {DIGITO}+"."{DIGITO}+
ID          {LETRA}({LETRA}|{DIGITO})*

%%

"//"[^\n]* { /* ignora comentários de linha inteira com segurança */ }
"\n"            { linha++; } 
[ \t\r\xa0]+    { /* ignora espaços, tabs, quebras do windows e espaços fantasmas */ }

"int"       { return TK_TIPO_INT; } 
"float"     { return TK_TIPO_FLOAT; } 
"char"      { return TK_TIPO_CHAR; }
"string"    { return TK_TIPO_STRING; }
"bool"      { return TK_TIPO_BOOL; }
"var"       { return TK_VAR; }

"true"      { return TK_TRUE; } 
"false"     { return TK_FALSE; }

"print"     { return TK_PRINT; }
"read"      { return TK_READ; }

"if"        { return TK_IF; }
"else"      { return TK_ELSE; }
"while"     { return TK_WHILE; }
"for"       { return TK_FOR; }
"do"        { return TK_DO; }
"foreach"   { return TK_FOREACH; }

"break"     { return TK_BREAK; }
"continue"  { return TK_CONTINUE; }

"switch"    { return TK_SWITCH; }
"case"      { return TK_CASE; }
"default"   { return TK_DEFAULT; }

"return"    { return TK_RETURN; }
"void"      { return TK_VOID; }

{NUM_FLOAT} { yylval.label = yytext; yylval.tipo = "float"; return TK_NUM; }
{NUM_INT}   { yylval.label = yytext; yylval.tipo = "int";   return TK_NUM; } 

{ID}        { yylval.label = yytext; return TK_ID; }

"+="        { return TK_MAIS_IGUAL; }
"-="        { return TK_MENOS_IGUAL; }
"*="        { return TK_VEZES_IGUAL; }
"/="        { return TK_DIV_IGUAL; }

"++"        { return TK_INC; }
"--"        { return TK_DEC; }

"+"         { return '+'; }
"-"         { return '-'; }
"*"         { return '*'; }
"/"         { return '/'; }
"**"        { return TK_POW; }
"%"         { return TK_MOD; }

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
"["         { return '['; }
"]"         { return ']'; }
"{"         { return '{'; }
"}"         { return '}'; }
":"         { return ':'; }
";"         { return ';'; }
","         { return ','; }

.           {
                fprintf(stdout, "Erro lexico na linha %d: caractere invalido '%s'\n", linha, yytext);
                fprintf(stderr, "Erro lexico na linha %d: caractere invalido '%s'\n", linha, yytext);
                houveErro = true;
            }

%%