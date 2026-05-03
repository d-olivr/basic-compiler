%{
#include <string>
#include <stdio.h>

/* estrutura de atributos para os tokens */
struct atributos {
    std::string label;
    std::string traducao;
    std::string tipo;
};

#define YYSTYPE atributos

#include "y.tab.h"

/* usando extern para a variavel que ja existe no sintatico.y */
extern int linha;
%}

%option noyywrap


    /* -------------------- EXPRESSÃO REGULAR PARA CADA TOKEN -------------------- */

ESPACO      [ \t]
/* espaco em branco é definido como um token, mas é ignorado no processamento */

DIGITO      [0-9]
/* números de 0 a 9 são tokens, mas são partes de outros tokens como NUM_INT e NUM_FLOAT */

LETRA       [a-zA-Z_]
/* letras maiúsculas, minúsculas e underscore são tokens, mas são partes de outros tokens como ID */

DELIM       {ESPACO}+
/*um ou mais espaços em branco são delimitadores, mas são ignorados no processamento */

NUM_INT     {DIGITO}+
/* uma sequência de um ou mais dígitos é um número inteiro */

NUM_FLOAT   {DIGITO}+"."{DIGITO}+
/* um float é definido como uma sequência de um ou mais dígitos, seguida por um ponto e outra sequência de um ou mais dígitos */

ID          {LETRA}({LETRA}|{DIGITO})*
/* um identificador é definido como uma letra seguida por zero ou mais letras ou dígitos */

%%

"\n"        { linha++; } /* contador de linhas para usarmos nas mensagens de erro */



{DELIM}     { }

    /* -------------------- PALAVRAS RESERVADAS -------------------- */ 

"int"       { return TK_TIPO_INT; } /*"int" é palavra reservada para o tipo inteiro*/
"float"     { return TK_TIPO_FLOAT; } /* a mesma lógica segue para os outros tipos */
"char"      { return TK_TIPO_CHAR; }
"bool"      { return TK_TIPO_BOOL; }
"true"      { yylval.label = "1"; yylval.tipo = "bool"; return TK_TRUE; } /* "true" é palavra reservada e 1 é o valor booleano correspondente */
"false"     { yylval.label = "0"; yylval.tipo = "bool"; return TK_FALSE; } /* mesma lógica segue para "false" */
  

    /* ------------------------ TOKENS ------------------------ */
{NUM_FLOAT} { yylval.label = yytext; yylval.tipo = "float"; return TK_NUM; } /* um número float é reconhecido e seu valor é armazenado em yylval.label, e seu tipo é armazenado em yylval.tipo */
{NUM_INT}   { yylval.label = yytext; yylval.tipo = "int";   return TK_NUM; } /* a mesma lógica segue para int */
{ID}        { yylval.label = yytext; return TK_ID; }

    /* -------------------- OPERADORES E SIMBOLOS -------------------- */
    /* operadores aritméticos */
"+"         { return '+'; }
"-"         { return '-'; }
"*"         { return '*'; }
"/"         { return '/'; }

    /* operadores lógicos */
"&&"        { return TK_E; }
"||"        { return TK_OU; }
"!"         { return TK_NAO; }

    /* operadores de comparação */
"=="        { return TK_IGUAL; }
"!="        { return TK_DIFERENTE; }
"<="        { return TK_MENOR_IGUAL; }
">="        { return TK_MAIOR_IGUAL; }
"<"         { return '<'; }
">"         { return '>'; }

    /* operador de atribuição */
"="         { return TK_ATRIB; }

    /* outros símbolos */
"("         { return '('; }
")"         { return ')'; }
":"         { return ':'; }
[;]         { return *yytext; }

    /* -------------------- TRATAMENTO DE ERROS LÉXICOS -------------------- */
    /* se um caractere não corresponde a nenhum dos padrões anteriores, é um erro léxico que vai ser identificado na msg abaixo */
.           { fprintf(stderr, "Caractere nao reconhecido na linha %d: %s\n", linha, yytext); }

%%