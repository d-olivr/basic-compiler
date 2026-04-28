%{
#include <string>
%}

%option noyywrap

ESPACO [ \t]
DIGITO [0-9]
LETRA  [a-zA-Z_]

DELIM {ESPACO}+
NUM   {DIGITO}+
ID    {LETRA}({LETRA}|{DIGITO})*   /* identificador: começa com letra */

%%

"\n"        { linha++; }
{DELIM}     {}

/* Palavra reservada: deve vir ANTES da regra de ID */
"int"       { return TK_INT; }

/* Identificador genérico */
{ID}        { yylval.label = yytext; return TK_ID; }


/* Operadores aritméticos */

/* ER: se leu + -> yytext = "+", retorna "+"*/
[+\-*/] { return *yytext; } /* adicionando \ antes do operador "-" pois ele sozinho pode indicar intervalo */

/* Parênteses */
[()] { return *yytext; }


{NUM}       { yylval.label = yytext; return TK_NUM; }

.           { fprintf(stderr, "Caractere nao reconhecido na linha %d: %s\n", linha, yytext); }

%%