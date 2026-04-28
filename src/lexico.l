%{
#include <string>
#include "sintatico.tab.h" /* gerado pelo yacc, contém os defines dos tokens */

%}

%option noyywrap

ESPACO [ \t]
DIGITO [0-9]
LETRA [a-zA-Z_]

DELIM {ESPACO}+
NUM_INT {DIGITO}+
NUM_FLOAT {DIGITO}+"."{DIGITO}+
ID {LETRA}({LETRA}|{DIGITO})*

%%

"\n"		{ linha++; }

{DELIM} 	{}


/* ────────── Palavras-chave de tipo ────────── */
/* ficam ANTES da regra de ID, senão "int" seria reconhecido como identificador */

"int"       { return TK_TIPO_INT; }
"float"     { return TK_TIPO_FLOAT; }
"char"      { return TK_TIPO_CHAR; }
"bool"      { return TK_TIPO_BOOL; }
"true"      { yylval.label = "1"; yylval.tipo = "bool"; return TK_TRUE; }
"false"     { yylval.label = "0"; yylval.tipo = "bool"; return TK_FALSE; }


/* ────────── Identificadores ────────── */
{ID}        { yylval.label = yytext; return TK_ID; }

/* --------- Operadores aritméticos -------------*/

{NUM_FLOAT} { yylval.label = yytext; yylval.tipo = "float"; return TK_NUM; }
{NUM_INT}   { yylval.label = yytext; yylval.tipo = "int";   return TK_NUM; }

/* ER: se leu + -> yytext = "+", retorna "+"*/
[+\-*/] { return *yytext; } /* adicionando \ antes do operador "-" pois ele sozinho pode indicar intervalo */

/* ────────── Operadores lógicos ────────── */
"&&" { return TK_E; }
"||" { return TK_OU; }
"!" { return TK_NAO; }

/* ────────── Operadores relacionais ────────── */
"==" { return TK_IGUAL; }
"!=" { return TK_DIFERENTE; }
"<=" { return TK_MENOR_IGUAL; }
">=" { return TK_MAIOR_IGUAL; }
[<>] { return *yytext; }

/* ────────── Atribuição ────────── */
"=" { return TK_ATRIB; }

/* ────────── Pontuação ────────── */

[():] { return *yytext; }

/* ────────── Erro ────────── */
. { fprintf(stderr, "Caractere nao reconhecido na linha %d: %s\n", linha, yytext); }

%%
