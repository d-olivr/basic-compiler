%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* A definição de YYSTYPE e o include do h devem vir antes do lex.yy.c */
#include "sintatico.tab.h"

int linha = 1;

/* Função manual para duplicar strings sem usar strlen */
/* Usa malloc e strcpy (permitidos) e o yyleng do Flex */

char* criar_string(const char* s, int tam) {
    char* novo = (char*) malloc(tam + 1);
    if (novo != NULL) {
        strcpy(novo, s);
    }
    return novo;
}
%}

%option noyywrap

/* Definições de nomes para as Expressões Regulares */
ESPACO    [ \t\r]
DIGITO    [0-9]
LETRA     [a-zA-Z_]

NUM_INT   {DIGITO}+
NUM_FLOAT {DIGITO}+"."{DIGITO}+
ID        {LETRA}({LETRA}|{DIGITO})*
LIT_CHAR  "'"({LETRA}|{DIGITO}|[ !@#$%^&*()])"'"

%%

    /* --- Tratamento de Quebras de Linha e Espaços --- */
"\n"          { linha++; }
{ESPACO}+     { /* ignora espaços */ }

    /* --- Comentários --- */
"//".*        { /* ignora linha única */ }
"/*"          { 
                int c;
                while ((c = input()) != 0) {
                    if (c == '\n') linha++;
                    else if (c == '*') {
                        if ((c = input()) == '/') break;
                        else unput(c);
                    }
                }
              }

    /* --- Palavras-chave de tipo --- */
"int"         { return TK_TIPO_INT; }
"float"       { return TK_TIPO_FLOAT; }
"char"        { return TK_TIPO_CHAR; }
"bool"        { return TK_TIPO_BOOL; }

    /* --- Literais e Identificadores --- */
"true"        { 
                yylval.label = criar_string("true", 4); 
                yylval.tipo = criar_string("bool", 4); 
                return TK_TRUE; 
              }
"false"       { 
                yylval.label = criar_string("false", 5); 
                yylval.tipo = criar_string("bool", 4); 
                return TK_FALSE; 
              }

{LIT_CHAR}    { 
                yylval.label = criar_string(yytext, yyleng); 
                yylval.tipo = criar_string("char", 4); 
                return TK_LIT_CHAR; 
              }

{NUM_FLOAT}   { 
                yylval.label = criar_string(yytext, yyleng); 
                yylval.tipo = criar_string("float", 5); 
                return TK_NUM; 
              }
{NUM_INT}     { 
                yylval.label = criar_string(yytext, yyleng); 
                yylval.tipo = criar_string("int", 3); 
                return TK_NUM; 
              }

{ID}          { 
                yylval.label = criar_string(yytext, yyleng); 
                return TK_ID; 
              }

    /* --- Operadores e Pontuação --- */
"+"           { return '+'; }
"-"           { return '-'; }
"*"           { return '*'; }
"/"           { return '/'; }

"&&"          { return TK_E; }
"||"          { return TK_OU; }
"!"           { return TK_NAO; }

"=="          { return TK_IGUAL; }
"!="          { return TK_DIFERENTE; }
"<="          { return TK_MENOR_IGUAL; }
">="          { return TK_MAIOR_IGUAL; }
"<"           { return '<'; }
">"           { return '>'; }

"="           { return TK_ATRIB; }
"("           { return '('; }
")"           { return ')'; }
":"           { return ':'; }
";"           { return ';'; }

    /* --- Erro Léxico --- */
.             { fprintf(stderr, "Erro lexico na linha %d: caractere [%s] invalido\n", linha, yytext); }

%%