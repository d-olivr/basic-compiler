%{
#include <string>
%}

%option noyywrap

ESPACO [ \t]
DIGITO [0-9]

DELIM {ESPACO}+
NUM {DIGITO}+

%%

"\n"		{ linha++; }

{DELIM} 	{}

/* --------- Operadores aritméticos -------------*/

/* ER: se leu + -> yytext = "+", retorna "+"*/
[+\-*/] { return *yytext; } /* adicionando \ antes do operador "-" pois ele sozinho pode indicar intervalo */

/* Parênteses */
[()] { return *yytext; }

{NUM}		{ yylval.label = yytext; return TK_NUM; }

.			{ fprintf(stderr, "Caractere nao reconhecido na linha %d: %s\n", linha, yytext); }

%%
