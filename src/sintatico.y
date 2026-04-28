%{
#include <iostream>
#include <string>
#include <stdio.h>

#define YYSTYPE atributos
using namespace std;

int var_temp_qnt;
int linha = 1;
string codigo_gerado;

struct atributos {
    string label;
    string traducao;
};

int yylex(void);
void yyerror(string);
string gentempcode();

*/ leitura de arquivo */
extern FILE *yyin;
%}

/* Novos tokens */
%token TK_NUM
%token TK_ID
%token TK_INT

%start S

%left '+' '-'
%left '*' '/'

%%

/*
 * S -> lista de statements (declarações ou expressões)
 * ou seja, isso permite múltiplas linhas no programa fonte
 */
S : LISTA_STMT
    {
        codigo_gerado  = "/*Compilador FOCA*/\n";
        codigo_gerado += "#include <stdio.h>\n";
        codigo_gerado += "int main(void) {\n";
        codigo_gerado += $1.traducao;
        codigo_gerado += "\treturn 0;\n}\n";
    }
    ;

LISTA_STMT
    : STMT                      { $$.traducao = $1.traducao; }
    | LISTA_STMT STMT           { $$.traducao = $1.traducao + $2.traducao; }
    ;

STMT
    : DECL                      { $$.traducao = $1.traducao; }
    | E ';'                     { $$.traducao = $1.traducao; }
    ;

/*
 * declaração: int x;  ou  int x, y, z;
 * TK_INT abre, LISTA_IDS lista os nomes, ';' fecha
 */
DECL
    : TK_INT LISTA_IDS ';'
        {
            /* gera "int x, y, z;\n" no C de saída */
            $$.traducao = "\tint " + $2.label + ";\n";
        }
    ;

/*
 * lista de identificadores separados por vírgula
 * TK_ID é um identificador, ou seja, um nome de variável
 * a regra recursiva permite uma lista de um ou mais identificadores
 */
LISTA_IDS
    : TK_ID
        {
            $$.label = $1.label;
        }
    | LISTA_IDS ',' TK_ID
        {
            $$.label = $1.label + ", " + $3.label;
        }
    ;

S 			: E
			{
				codigo_gerado = "/*Compilador FOCA*/\n"
								"#include <stdio.h>\n"
								"int main(void) {\n";

				codigo_gerado += $1.traducao;

				codigo_gerado += "\treturn 0;\n";
				codigo_gerado += "}\n";
			}
			;
E /* $$*/: E /* $1*/ '+' E /* $2* -> uma expressão E pode ser formada por uma expressão seguida de um símbolo "+", seguida de outra expressão */
			{
				$$.label = gentempcode(); /* cria um nome único de variável temporária para o resultado dessa conta, vai trazer em traducao tudo q é necessário p/ fazer  aconta*/
				$$.traducao = $1.traducao + $3.traducao + "\t" + $$.label /*T3*/ + /* .traducao -> traz todas as linhas de comandos necessarios p executar a conta */
					" = " + $1.label  /* T1*/+ " + " + $3.label /*T2*/ + ";\n"; 
					/* t3 = t2 + t1 */
			}
			|
			 E '-' E {
				$$.label = gentempcode();
				$$.traducao = $1.traducao + $3.traducao + "\t" + $$.label +
					" = " + $1.label + " - " + $3.label + ";\n";
			}
			| 
			 E '/' E {
				$$.label = gentempcode();
				$$.traducao = $1.traducao + $3.traducao + "\t" + $$.label +
					" = " + $1.label + " / " + $3.label + ";\n";
			}
			|
			 E '*' E {
				$$.label = gentempcode();
				$$.traducao = $1.traducao + $3.traducao + "\t" + $$.label +
					" = " + $1.label + " * " + $3.label + ";\n";
			}

			| '(' E ')' { /* uma expressão (E) pode ser formada por um ( seguido de outra expressão E, seguido de um ) */
				$$.label = $2.label; /* o resultado do parentese é o mesmo valor da expressao interna */
				$$.traducao = $2.traducao; /* o código gerado é exatamente o mesmo da expressão interna	*/
			}

			| TK_NUM
			{
				$$.label = $1.label;
				$$.traducao = "";
			}
			;

%%

#include "lex.yy.c"

string gentempcode() {
    var_temp_qnt++;
    return "t" + to_string(var_temp_qnt);
}

int main(int argc, char* argv[]) {
    var_temp_qnt = 0;
    if (argc > 1) {
        yyin = fopen(argv[1], "r");
        if (!yyin) { perror("Erro ao abrir arquivo"); return 1; }
    }
    if (yyparse() == 0) cout << codigo_gerado;
    return 0;
}

void yyerror(string MSG) {
    cerr << "Erro na linha " << linha << ": " << MSG << endl;
}