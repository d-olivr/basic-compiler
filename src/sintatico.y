%{
#include <iostream>
#include <string>
#include <stdio.h>
#include <map>
#include <stack>
#include <string.h> // Para usar strcpy e strcat se for necessário

/* Estrutura pros atributos dos tokens e não-terminais */
struct atributos {
	std::string label;
	std::string traducao;
	std::string tipo;
};

#define YYSTYPE atributos

using namespace std;

/* Variáveis Globais */
int var_temp_qnt = 0;
extern int linha; // Vem do Flex
string codigo_gerado;

/* Estrutura da Tabela de Símbolos */
struct Variavel {
	string tipo;
	string label;
};

stack<map<string, Variavel>> pilhaEscopos;

/* Funções de Escopo */
void entrarEscopo() {
	pilhaEscopos.push(map<string, Variavel>());
}

void sairEscopo() {
	if (!pilhaEscopos.empty()) pilhaEscopos.pop();
}

void declararVariavel(string nome, string tipo, string label) {
	pilhaEscopos.top()[nome] = {tipo, label};
}

Variavel* buscarVariavel(string nome) {
	stack<map<string, Variavel>> copia = pilhaEscopos;
	while (!copia.empty()) {
		if (copia.top().count(nome)) {
			return &copia.top()[nome];
		}
		copia.pop();
	}
	return nullptr;
}

/* Lógica de Promoção de Tipos (Conversão Implícita) */
string tipoResultante(string t1, string t2) {
	if (t1 == t2) return t1;
	// Regra: float + int = float
	if ((t1 == "float" && t2 == "int") || (t1 == "int" && t2 == "float")) return "float";
	// Regra: int + bool = int
	if ((t1 == "bool" && t2 == "int") || (t1 == "int" && t2 == "bool")) return "int";
	return t1; // Simplificação para outros casos
}

/* Protótipos */
int yylex(void);
void yyerror(string);
string gentempcode();
extern FILE *yyin;
%}

/* Tokens vindo do Flex */
%token TK_NUM TK_ID TK_LIT_CHAR
%token TK_TIPO_INT TK_TIPO_FLOAT TK_TIPO_BOOL TK_TIPO_CHAR
%token TK_TRUE TK_FALSE
%token TK_ATRIB TK_E TK_OU TK_NAO
%token TK_IGUAL TK_DIFERENTE TK_MENOR_IGUAL TK_MAIOR_IGUAL

%start S

/* Precedência para o Código Intermediário */
%left TK_OU
%left TK_E
%left TK_IGUAL TK_DIFERENTE
%left '<' '>' TK_MENOR_IGUAL TK_MAIOR_IGUAL
%left '+' '-'
%left '*' '/'
%right TK_NAO

%%

S
	: lista_comandos
	{
		codigo_gerado = "/* Compilador Gerado */\n"
						"#include <stdio.h>\n"
						"#include <stdbool.h>\n\n"
						"int main(void) {\n" + $1.traducao + 
						"\treturn 0;\n}\n";
	}
	;

lista_comandos
	: lista_comandos comando { $$.traducao = $1.traducao + $2.traducao; }
	| { $$.traducao = ""; }
	;

comando
	: declaracao
	| atribuicao
	| E ';' { $$.traducao = $1.traducao; }
	;

tipo
	: TK_TIPO_INT   { $$.tipo = "int";   $$.label = "int"; }
	| TK_TIPO_FLOAT { $$.tipo = "float"; $$.label = "float"; }
	| TK_TIPO_BOOL  { $$.tipo = "bool";  $$.label = "int"; }
	| TK_TIPO_CHAR  { $$.tipo = "char";  $$.label = "char"; }
	;

/* Missão: Declaração e Conversão Explícita (Cast) */
declaracao
	: tipo TK_ID ';'
	{
		declararVariavel($2.label, $1.tipo, $2.label);
		$$.traducao = "\t" + $1.label + " " + $2.label + ";\n";
	}
	| tipo TK_ID TK_ATRIB E ';'
	{
		declararVariavel($2.label, $1.tipo, $2.label);
		// Aqui forçamos o cast para o tipo da variável declarada
		$$.traducao = $4.traducao + "\t" + $1.label + " " + $2.label + " = (" + $1.label + ")" + $4.label + ";\n";
	}
	;

atribuicao
	: TK_ID TK_ATRIB E ';'
	{
		Variavel* v = buscarVariavel($1.label);
		if (!v) yyerror("Variavel nao declarada: " + $1.label);
		string t = v ? v->tipo : "int";
		// Cast implícito na atribuição
		$$.traducao = $3.traducao + "\t" + $1.label + " = (" + t + ")" + $3.label + ";\n";
	}
	;

/* Missão: Expressões e Código Intermediário (Temporárias) */
E
	: E '+' E { 
		$$.tipo = tipoResultante($1.tipo, $3.tipo);
		$$.label = gentempcode();
		$$.traducao = $1.traducao + $3.traducao + "\t" + $$.tipo + " " + $$.label + " = " + $1.label + " + " + $3.label + ";\n";
	}
	| E '-' E { 
		$$.tipo = tipoResultante($1.tipo, $3.tipo);
		$$.label = gentempcode();
		$$.traducao = $1.traducao + $3.traducao + "\t" + $$.tipo + " " + $$.label + " = " + $1.label + " - " + $3.label + ";\n";
	}
	| E '*' E { 
		$$.tipo = tipoResultante($1.tipo, $3.tipo);
		$$.label = gentempcode();
		$$.traducao = $1.traducao + $3.traducao + "\t" + $$.tipo + " " + $$.label + " = " + $1.label + " * " + $3.label + ";\n";
	}
	| E '/' E { 
		$$.tipo = tipoResultante($1.tipo, $3.tipo);
		$$.label = gentempcode();
		$$.traducao = $1.traducao + $3.traducao + "\t" + $$.tipo + " " + $$.label + " = " + $1.label + " / " + $3.label + ";\n";
	}
	| TK_NUM { 
		$$.label = $1.label; 
		$$.tipo = $1.tipo; // Vem do Flex já com "int" ou "float"
		$$.traducao = ""; 
	}
	| TK_ID {
		Variavel* v = buscarVariavel($1.label);
		if (!v) yyerror("Variavel nao declarada: " + $1.label);
		$$.label = $1.label;
		$$.tipo = v ? v->tipo : "int";
		$$.traducao = "";
	}
	| TK_LIT_CHAR {
		$$.label = $1.label;
		$$.tipo = "char";
		$$.traducao = "";
	}
	| '(' E ')' { $$ = $2; }
	;

%%

/* Incluindo o código gerado pelo Flex */
#include "lex.yy.c"

string gentempcode() {
	return "t" + to_string(var_temp_qnt++);
}

void yyerror(string MSG) {
	cerr << "Erro na linha " << linha << ": " << MSG << endl;
}

int main(int argc, char* argv[]) {
	entrarEscopo();
	if (argc > 1) yyin = fopen(argv[1], "r");
	
	if (yyparse() == 0) cout << codigo_gerado << endl;
	
	return 0;
}