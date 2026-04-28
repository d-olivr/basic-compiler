%{
#include <iostream>
#include <string>
#include <stdio.h>
#include <map>
#include <stack>

#define YYSTYPE atributos

using namespace std;

int var_temp_qnt;
int linha = 1;
string codigo_gerado;

struct atributos
{
	string label;
	string traducao;
	string tipo;
};

struct Variavel {
	string tipo;
	string label;
};

stack<map<string, Variavel>> pilhaEscopos;

void entrarEscopo() {
	pilhaEscopos.push(map<string, Variavel>());
}

void sairEscopo() {
	pilhaEscopos.pop();
}

void declararVariavel(string nome, string tipo, string label) {
	pilhaEscopos.top()[nome] = {tipo, label};
}

Variavel* buscarVariavel(string nome) {
	auto copia = pilhaEscopos;
	while (!copia.empty()) {
		if (copia.top().count(nome)) return &pilhaEscopos.top()[nome];
		copia.pop();
	}
	return nullptr;
}

string tipoResultante(string t1, string t2) {
	if (t1 == t2) return t1;
	if ((t1 == "float" && t2 == "int") ||
		(t1 == "int"   && t2 == "float")) return "float";
	if ((t1 == "bool"  && t2 == "int") ||
		(t1 == "int"   && t2 == "bool")) return "int";
	return "erro";
}

int yylex(void);
void yyerror(string);
string gentempcode();

extern FILE *yyin;
%}

%token TK_NUM
%token TK_ID
%token TK_TIPO_INT
%token TK_TIPO_FLOAT
%token TK_TIPO_BOOL
%token TK_TIPO_CHAR
%token TK_TRUE
%token TK_FALSE
%token TK_ATRIB
%token TK_E
%token TK_OU
%token TK_NAO
%token TK_IGUAL
%token TK_DIFERENTE
%token TK_MENOR_IGUAL
%token TK_MAIOR_IGUAL

%start S

%left TK_OU
%left TK_E
%left TK_IGUAL TK_DIFERENTE
%left '<' '>' TK_MENOR_IGUAL TK_MAIOR_IGUAL
%left '+' '-'
%left '*' '/'
%right TK_NAO

%%

/* ── S aceita uma sequência de comandos ── */
S
	: lista_comandos
	{
		codigo_gerado = "/*Compilador FOCA*/\n"
						"#include <stdio.h>\n"
						"int main(void) {\n";
		codigo_gerado += $1.traducao;
		codigo_gerado += "\treturn 0;\n";
		codigo_gerado += "}\n";
	}
	;

/* ── lista de comandos: declarações, atribuições ou expressões ── */
lista_comandos
	: lista_comandos declaracao
	{
		$$.traducao = $1.traducao + $2.traducao;
	}
	| lista_comandos atribuicao
	{
		$$.traducao = $1.traducao + $2.traducao;
	}
	| lista_comandos E ';'
	{
		$$.traducao = $1.traducao + $2.traducao;
	}
	| /* vazio */
	{
		$$.traducao = "";
	}
	;

/* ── tipos primitivos ── */
tipo
	: TK_TIPO_INT   { $$.tipo = "int";   $$.label = "int"; }
	| TK_TIPO_FLOAT { $$.tipo = "float"; $$.label = "float"; }
	| TK_TIPO_BOOL  { $$.tipo = "bool";  $$.label = "int"; } /* bool vira int internamente */
	| TK_TIPO_CHAR  { $$.tipo = "char";  $$.label = "char"; }
	;

/* ── declaração de variável ── */
declaracao
	: tipo TK_ID ';'
	{
		string varLabel = $2.label;
		declararVariavel($2.label, $1.tipo, varLabel);
		$$.traducao = "\t" + $1.label + " " + varLabel + ";\n";
		$$.label = varLabel;
		$$.tipo = $1.tipo;
	}
	| tipo TK_ID TK_ATRIB E ';'
	{
		string varLabel = $2.label;
		declararVariavel($2.label, $1.tipo, varLabel);
		$$.traducao = $4.traducao +
					  "\t" + $1.label + " " + varLabel + " = " + $4.label + ";\n";
		$$.label = varLabel;
		$$.tipo = $1.tipo;
	}
	;

/* ── atribuição de variável já declarada ── */
atribuicao
	: TK_ID TK_ATRIB E ';'
	{
		Variavel* v = buscarVariavel($1.label);
		if (!v) yyerror("Variavel nao declarada: " + $1.label);
		$$.traducao = $3.traducao +
					  "\t" + $1.label + " = " + $3.label + ";\n";
		$$.label = $1.label;
		$$.tipo = v ? v->tipo : "";
	}
	;

/* ── expressões (aritméticas, lógicas, relacionais) ── */
E
	: E '+' E
	{
		$$.label = gentempcode();
		$$.tipo = tipoResultante($1.tipo, $3.tipo);
		$$.traducao = $1.traducao + $3.traducao +
					  "\t" + $$.tipo + " " + $$.label +
					  " = " + $1.label + " + " + $3.label + ";\n";
	}
	| E '-' E
	{
		$$.label = gentempcode();
		$$.tipo = tipoResultante($1.tipo, $3.tipo);
		$$.traducao = $1.traducao + $3.traducao +
					  "\t" + $$.tipo + " " + $$.label +
					  " = " + $1.label + " - " + $3.label + ";\n";
	}
	| E '*' E
	{
		$$.label = gentempcode();
		$$.tipo = tipoResultante($1.tipo, $3.tipo);
		$$.traducao = $1.traducao + $3.traducao +
					  "\t" + $$.tipo + " " + $$.label +
					  " = " + $1.label + " * " + $3.label + ";\n";
	}
	| E '/' E
	{
		$$.label = gentempcode();
		$$.tipo = tipoResultante($1.tipo, $3.tipo);
		$$.traducao = $1.traducao + $3.traducao +
					  "\t" + $$.tipo + " " + $$.label +
					  " = " + $1.label + " / " + $3.label + ";\n";
	}
	/* ── lógicos ── */
	| E TK_E E
	{
		$$.label = gentempcode();
		$$.tipo = "bool";
		$$.traducao = $1.traducao + $3.traducao +
					  "\tint " + $$.label +
					  " = " + $1.label + " && " + $3.label + ";\n";
	}
	| E TK_OU E
	{
		$$.label = gentempcode();
		$$.tipo = "bool";
		$$.traducao = $1.traducao + $3.traducao +
					  "\tint " + $$.label +
					  " = " + $1.label + " || " + $3.label + ";\n";
	}
	| TK_NAO E
	{
		$$.label = gentempcode();
		$$.tipo = "bool";
		$$.traducao = $2.traducao +
					  "\tint " + $$.label + " = !" + $2.label + ";\n";
	}
	/* ── relacionais ── */
	| E TK_IGUAL E
	{
		$$.label = gentempcode();
		$$.tipo = "bool";
		$$.traducao = $1.traducao + $3.traducao +
					  "\tint " + $$.label +
					  " = " + $1.label + " == " + $3.label + ";\n";
	}
	| E TK_DIFERENTE E
	{
		$$.label = gentempcode();
		$$.tipo = "bool";
		$$.traducao = $1.traducao + $3.traducao +
					  "\tint " + $$.label +
					  " = " + $1.label + " != " + $3.label + ";\n";
	}
	| E '<' E
	{
		$$.label = gentempcode();
		$$.tipo = "bool";
		$$.traducao = $1.traducao + $3.traducao +
					  "\tint " + $$.label +
					  " = " + $1.label + " < " + $3.label + ";\n";
	}
	| E '>' E
	{
		$$.label = gentempcode();
		$$.tipo = "bool";
		$$.traducao = $1.traducao + $3.traducao +
					  "\tint " + $$.label +
					  " = " + $1.label + " > " + $3.label + ";\n";
	}
	| E TK_MENOR_IGUAL E
	{
		$$.label = gentempcode();
		$$.tipo = "bool";
		$$.traducao = $1.traducao + $3.traducao +
					  "\tint " + $$.label +
					  " = " + $1.label + " <= " + $3.label + ";\n";
	}
	| E TK_MAIOR_IGUAL E
	{
		$$.label = gentempcode();
		$$.tipo = "bool";
		$$.traducao = $1.traducao + $3.traducao +
					  "\tint " + $$.label +
					  " = " + $1.label + " >= " + $3.label + ";\n";
	}
	/* ── parênteses ── */
	| '(' E ')'
	{
		$$.label = $2.label;
		$$.tipo = $2.tipo;
		$$.traducao = $2.traducao;
	}
	/* ── valores literais ── */
	| TK_NUM
	{
		$$.label = $1.label;
		$$.tipo = $1.tipo; /* o lexico.l deve preencher o tipo: "int" ou "float" */
		$$.traducao = "";
	}
	| TK_TRUE
	{
		$$.label = "1";
		$$.tipo = "bool";
		$$.traducao = "";
	}
	| TK_FALSE
	{
		$$.label = "0";
		$$.tipo = "bool";
		$$.traducao = "";
	}
	/* ── variável ── */
	| TK_ID
	{
		Variavel* v = buscarVariavel($1.label);
		if (!v) yyerror("Variavel nao declarada: " + $1.label);
		$$.label = $1.label;
		$$.tipo = v ? v->tipo : "";
		$$.traducao = "";
	}
	;

%%

#include "lex.yy.c"

int yyparse();

string gentempcode()
{
	var_temp_qnt++;
	return "t" + to_string(var_temp_qnt);
}

int main(int argc, char* argv[])
{
	var_temp_qnt = 0;
	entrarEscopo();

	if (argc > 1)
	{
		yyin = fopen(argv[1], "r");
		if (!yyin)
		{
			perror("Erro ao abrir arquivo");
			return 1;
		}
	}

	if (yyparse() == 0)
		cout << codigo_gerado;

	sairEscopo();
	return 0;
}

void yyerror(string MSG)
{
	cerr << "Erro na linha " << linha << ": " << MSG << endl;
}
