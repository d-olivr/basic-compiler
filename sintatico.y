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

struct atributos {
    string label;
    string traducao;
	string tipo;
};

struct Variavel {
	string tipo;
	string label;
};
/* ---------- ESTRUTURA DE VARIÁVEIS E PILHA DE ESCOPO ---------- */
/* a pilha de escopos é uma estrutura de dados que armazena um mapa para 
cada escopo do programa, onde o mapa associa o nome de cada variável 
declarada no escopo ao seu tipo e rótulo (label) */
stack<map<string, Variavel>> pilhaEscopos;

/* funções para manipular a pilha de escopos
sao usada para controlar as variáveis declaradas em cada escopo do programa (funcoes, blocos, etc.) */
void entrarEscopo() {
	pilhaEscopos.push(map<string, Variavel>());
}

void sairEscopo() {
	pilhaEscopos.pop();
}

/* função para declarar uma variável no escopo atual (topo da pilha), associando seu nome a um tipo e um rótulo (label) que será usado na geração de código */
void declararVariavel(string nome, string tipo, string label) {
	pilhaEscopos.top()[nome] = {tipo, label};
}

/* função para buscar uma variável na pilha de escopos, começando do escopo mais interno (topo da pilha) e indo para os mais externos */
Variavel* buscarVariavel(string nome) {
	auto copia = pilhaEscopos;
	while (!copia.empty()) {
		if (copia.top().count(nome)) return &pilhaEscopos.top()[nome];
		copia.pop();
	}
	return nullptr;
}
/* -------------------- FUNCÕES AUXILIARES -------------------- */

/* conversão de tipos */
string tipoResultante(string t1, string t2) {
	if (t1 == t2) return t1;
	if ((t1 == "float" && t2 == "int") ||
		(t1 == "int"   && t2 == "float")) return "float";
	if ((t1 == "bool"  && t2 == "int") ||
		(t1 == "int"   && t2 == "bool")) return "int";
	return "erro";
}
/* ---------- FUNCÕES AUXILIARES PARA O PARSER ---------- */
int yylex(void);
void yyerror(string);
string gentempcode();/* função para gerar um rótulo (label) temporário, que é usado para armazenar o resultado de expressões intermediárias*/

/* ponteiro para o arquivo de onde o lexer vai ler */
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
/* -------------------------------- REGRAS DE PRODUÇÃO ---------------------------- */
/* a regra inicial da gramática é uma lista de comandos, que pode ser vazia 
ou conter várias declarações, atribuições ou expressões */
S
	: lista_comandos
	{
		codigo_gerado = "__________________________\n\n"
						"★  MIKU COMPILER (^_^)  ★\n"
						"__________________________\n\n"
						"#include <stdio.h>\n"
						"int main(void) {\n";
		codigo_gerado += $1.traducao;
		codigo_gerado += "\treturn 0;\n";
		codigo_gerado += "}\n";
	}
	;

/* -------------------- LISTA DE COMANDOS -------------------- */
lista_comandos
	: lista_comandos declaracao
	{
		$$.traducao = $1.traducao + $2.traducao;/* a tradução de uma lista de comandos é a concatenação das traduções de cada comando */
	}
	| lista_comandos atribuicao/* atribuição é um tipo de comando, então pode aparecer em uma lista de comandos */
	{
		$$.traducao = $1.traducao + $2.traducao;
	}
	| lista_comandos E ';'/* uma expressão seguida de ponto e vírgula também eh um comando, então pode aparecer em uma lista de comandos */
	{
		$$.traducao = $1.traducao + $2.traducao;
	}
	| /* a lista de comandos pode ser vazia, e nesse caso a tradução é uma string vazia */
	{
		$$.traducao = "";
	}
	;

/* TIPOS BÁSICOS */
tipo
	: TK_TIPO_INT   { $$.tipo = "int";   $$.label = "int"; }
	| TK_TIPO_FLOAT { $$.tipo = "float"; $$.label = "float"; }
	| TK_TIPO_BOOL  { $$.tipo = "bool";  $$.label = "int"; } /* bool vira int internamente */
	| TK_TIPO_CHAR  { $$.tipo = "char";  $$.label = "char"; }
	;

/* DECLARAÇÃO DE VARIÁVEL (com ou sem inicialização) */
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

/* ATRIBUIÇÃO DE VALOR A UMA VARIÁVEL JÁ DECLARADA */
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

/* -------------------- EXPRESSOES --------------------*/
/* ARITMETICAS */
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
	/* LOGICAS */
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
	/* RELACIONAIS */
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
	/* PARENTESIS */
	| '(' E ')'
	{
		$$.label = $2.label;
		$$.tipo = $2.tipo;
		$$.traducao = $2.traducao;
	}
	/* VALORES LITERAIS */
	| TK_NUM
	{
    	$$.label = gentempcode();/* gera t1, t2, etc. */
		$$.tipo = $1.tipo;
		$$.traducao = "\t" + $1.tipo + " " + $$.label + " = " + $1.label + ";\n";
	}
	| TK_TRUE
	{
		$$.label = gentempcode();
		$$.tipo = "bool";
		$$.traducao = "\tint " + $$.label + " = 1;\n";
	}
	| TK_FALSE
	{
		$$.label = gentempcode();
		$$.tipo = "bool";
		$$.traducao = "\tint " + $$.label + " = 0;\n";
	}
	/* VARIÁVEL */
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

/* função para gerar um rótulo (label) temporário, que é usado para armazenar o resultado de expressões intermediárias */
string gentempcode() {
    var_temp_qnt++;
    return "t" + to_string(var_temp_qnt);
}
/* ---------- FUNÇÃO PRINCIPAL ---------- 
- inicializa a pilha de escopos
- lê o arquivo de entrada (se fornecido)
- chama o parser */
int main(int argc, char* argv[])
{
	var_temp_qnt = 0;
	entrarEscopo();

	if (argc > 1)/* se um nome de arquivo for fornecido como argumento, o lexer vai ler desse arquivo em vez de ler da entrada padrão */
	{
		yyin = fopen(argv[1], "r");/* nome do arquivo é passado como argumento */
		if (!yyin)
		{
			perror("Erro ao abrir arquivo");
			return 1;
		}
	}

	if (yyparse() == 0)/* yyparse() retorna 0 se a análise sintática for bem-sucedida ou diferente de zero se houver um erro de sintaxe */
		cout << codigo_gerado;/* se a análise sintática for bem-sucedida, o código gerado vai ser impresso*/

	sairEscopo();
	return 0;
}
    /* -------------------- TRATAMENTO DE ERROS SINTATICOS -------------------- */
void yyerror(string MSG)
{
	cerr << "Erro na linha " << linha << ": " << MSG << endl;
}
