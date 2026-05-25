%{
#include <string>
#include <stdio.h>

/* Estrutura de atributos para os tokens (idêntica à do sintático) */
struct atributos {
    std::string label;
    std::string traducao;
    std::string tipo;
};

#define YYSTYPE atributos

#include "y.tab.h"

/* Variável global para contar as linhas, controlada pelo léxico */
int linha = 1; 
%}

%option noyywrap

/* -------------------- DEFINIÇÕES (EXPRESSÕES REGULARES) -------------------- */

DIGITO      [0-9]
LETRA       [a-zA-Z_]
NUM_INT     {DIGITO}+
NUM_FLOAT   {DIGITO}+"."{DIGITO}+
ID          {LETRA}({LETRA}|{DIGITO})*

%%

    /* Note o espaço antes de cada comentário nesta seção. É obrigatório! */

"\n"        { linha++; } 
[ \t]+      { /* ignora espaços em branco e tabulações */ }

    /* -------------------- PALAVRAS RESERVADAS -------------------- */ 
"int"       { return TK_TIPO_INT; } 
"float"     { return TK_TIPO_FLOAT; } 
"char"      { return TK_TIPO_CHAR; }
"bool"      { return TK_TIPO_BOOL; }

    /* O léxico apenas retorna o token. O tipo interno 'bool' é definido no Bison */
"true"      { return TK_TRUE; } 
"false"     { return TK_FALSE; }
  
    /* ------------------------ TOKENS DE VALORES ------------------------ */
\'.\'       { yylval.label = yytext; yylval.tipo = "char"; return TK_NUM; } 
{NUM_FLOAT} { yylval.label = yytext; yylval.tipo = "float"; return TK_NUM; } 
{NUM_INT}   { yylval.label = yytext; yylval.tipo = "int";   return TK_NUM; } 

    /* Passamos o nome do ID. A checagem de tipo ocorre na tabela de símbolos do Bison */
{ID}        { yylval.label = yytext; return TK_ID; }

    /* -------------------- OPERADORES E SÍMBOLOS -------------------- */
    /* Operadores aritméticos */
"+"         { return '+'; }
"-"         { return '-'; }
"*"         { return '*'; }
"/"         { return '/'; }

    /* Operadores lógicos */
"&&"        { return TK_E; }
"||"        { return TK_OU; }
"!"         { return TK_NAO; }

    /* Operadores de comparação */
"=="        { return TK_IGUAL; }
"!="        { return TK_DIFERENTE; }
"<="        { return TK_MENOR_IGUAL; }
">="        { return TK_MAIOR_IGUAL; }
"<"         { return '<'; }
">"         { return '>'; }

    /* Operador de atribuição */
"="         { return TK_ATRIB; }

    /* Outros símbolos */
"("         { return '('; }
")"         { return ')'; }
":"         { return ':'; }
";"         { return ';'; }

    /* -------------------- TRATAMENTO DE ERROS LÉXICOS -------------------- */
.           { fprintf(stderr, "Caractere nao reconhecido na linha %d: %s\n", linha, yytext); }

%%