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
string vars_temporarias = ""; /* variável de texto para guardar as variáveis temporárias*/

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
sao usadas para controlar as variáveis declaradas em cada escopo do programa (funcoes, blocos, etc.) */
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

/* ---------- ESTRUTURA PARA CONVERSÃO IMPLÍCITA (CAST) ---------- */
string gentempcode(); 

struct Cast {
    string label;
    string traducao;
};

Cast gerarCast(string label, string tipoOriginal, string tipoDestino) {
    Cast c;
    c.label = label;
    c.traducao = "";
    /* Se a conta pede float mas a variável é int, gera o "(float)" */
    if (tipoOriginal == "int" && tipoDestino == "float") {
        c.label = gentempcode();
        vars_temporarias += "\tfloat " + c.label + ";\n";
        c.traducao = "\t" + c.label + " = (float) " + label + ";\n";
    }
    return c;
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
                        
        /* 1. Injeta todas as declarações (int t1; int x;) no topo do main */
        codigo_gerado += vars_temporarias; 
        
        /* 2. Dá uma quebra de linha em branco para separar as declarações do resto do código */
        codigo_gerado += "\n";
        
        /* 3. Injeta as atribuições e expressões (t1 = 1; x = t1 + 2;) */
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
    | TK_TIPO_BOOL  { $$.tipo = "int";   $$.label = "int"; } /* Força o tipo a ser impresso como int */
    | TK_TIPO_CHAR  { $$.tipo = "char";  $$.label = "char"; }
    ;

/* DECLARAÇÃO DE VARIÁVEL (com ou sem inicialização) */
declaracao
    : tipo TK_ID ';'
    {
        string varLabel = gentempcode(); /* "A" ganha um rótulo como "t1" */
        declararVariavel($2.label, $1.tipo, varLabel);
        
        /* Manda "int t1;" para o topo do arquivo*/
        vars_temporarias += "\t" + $1.tipo + " " + varLabel + ";\n";
        
        $$.traducao = "";
        $$.label = varLabel;
        $$.tipo = $1.tipo;
    }
    | tipo TK_ID TK_ATRIB E ';'
    {
        string varLabel = gentempcode(); /* "A" vira "t1" */
        declararVariavel($2.label, $1.tipo, varLabel);
        
        /* Manda "int t1;" para o topo*/
        vars_temporarias += "\t" + $1.tipo + " " + varLabel + ";\n";
        
        /* Faz a atribuição usando o rótulo interno (t1 = ...)*/
        $$.traducao = $4.traducao +
                      "\t" + varLabel + " = " + $4.label + ";\n";
                      
        $$.label = varLabel;
        $$.tipo = $1.tipo;
    }
    ;

/* ATRIBUIÇÃO DE VALOR A UMA VARIÁVEL JÁ DECLARADA (Ou nova) */
atribuicao
    : TK_ID TK_ATRIB E ';'
    {
        Variavel* v = buscarVariavel($1.label);
        
        /* Se a variável existe na tabela, usa o "tX" dela. Se não, usa o próprio nome (ex: "A") */
        string targetLabel = v ? v->label : $1.label;
        
        $$.traducao = $3.traducao +
                      "\t" + targetLabel + " = " + $3.label + ";\n";
        $$.label = targetLabel;
        $$.tipo = v ? v->tipo : "int";
    }
    ;
/* -------------------- EXPRESSOES --------------------*/
/* ARITMETICAS */
E
    : E '+' E
    {
        $$.tipo = tipoResultante($1.tipo, $3.tipo);

        /* Gera os casts */
        Cast c1 = gerarCast($1.label, $1.tipo, $$.tipo);
        Cast c3 = gerarCast($3.label, $3.tipo, $$.tipo);

        /* Cria o temporário da conta */
        $$.label = gentempcode();
        vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";

        /* Monta a string na ordem: Esq -> Cast Esq -> Dir -> Cast Dir -> Soma */
        $$.traducao = $1.traducao + c1.traducao + 
                      $3.traducao + c3.traducao +
                      "\t" + $$.label + " = " + c1.label + " + " + c3.label + ";\n";
    }
    | E '-' E
    {
        $$.tipo = tipoResultante($1.tipo, $3.tipo);

        Cast c1 = gerarCast($1.label, $1.tipo, $$.tipo);
        Cast c3 = gerarCast($3.label, $3.tipo, $$.tipo);

        $$.label = gentempcode();
        vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";

        $$.traducao = $1.traducao + c1.traducao + 
                      $3.traducao + c3.traducao +
                      "\t" + $$.label + " = " + c1.label + " - " + c3.label + ";\n";
    }
    | E '*' E
    {
        $$.tipo = tipoResultante($1.tipo, $3.tipo);

        Cast c1 = gerarCast($1.label, $1.tipo, $$.tipo);
        Cast c3 = gerarCast($3.label, $3.tipo, $$.tipo);

        $$.label = gentempcode();
        vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";

        $$.traducao = $1.traducao + c1.traducao + 
                      $3.traducao + c3.traducao +
                      "\t" + $$.label + " = " + c1.label + " * " + c3.label + ";\n";
    }
    | E '/' E
    {
        $$.tipo = tipoResultante($1.tipo, $3.tipo);

        Cast c1 = gerarCast($1.label, $1.tipo, $$.tipo);
        Cast c3 = gerarCast($3.label, $3.tipo, $$.tipo);

        $$.label = gentempcode();
        vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";

        $$.traducao = $1.traducao + c1.traducao + 
                      $3.traducao + c3.traducao +
                      "\t" + $$.label + " = " + c1.label + " / " + c3.label + ";\n";
    }

    /* LOGICAS */
    | E TK_E E
    {
        $$.label = gentempcode();
        $$.tipo = "bool";
        vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao +
                      "\t" + $$.label + " = " + $1.label + " && " + $3.label + ";\n";
    }
    | E TK_OU E
    {
        $$.label = gentempcode();
        $$.tipo = "bool";
        vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao +
                      "\t" + $$.label + " = " + $1.label + " || " + $3.label + ";\n";
    }
    | TK_NAO E
    {
        $$.label = gentempcode();
        $$.tipo = "bool";
        vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $2.traducao +
                      "\t" + $$.label + " = !" + $2.label + ";\n";
    }
    /* RELACIONAIS */
    | E TK_IGUAL E
    {
        $$.label = gentempcode();
        $$.tipo = "bool";
        vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao +
                      "\t" + $$.label + " = " + $1.label + " == " + $3.label + ";\n";
    }
    | E TK_DIFERENTE E
    {
        $$.label = gentempcode();
        $$.tipo = "bool";
        vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao +
                      "\t" + $$.label + " = " + $1.label + " != " + $3.label + ";\n";
    }
    | E '<' E
    {
        $$.label = gentempcode();
        $$.tipo = "bool";
        vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao +
                      "\t" + $$.label + " = " + $1.label + " < " + $3.label + ";\n";
    }
    | E '>' E
    {
        $$.label = gentempcode();
        $$.tipo = "bool";
        vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao +
                      "\t" + $$.label + " = " + $1.label + " > " + $3.label + ";\n";
    }
    | E TK_MENOR_IGUAL E
    {
        $$.label = gentempcode();
        $$.tipo = "bool";
        vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao +
                      "\t" + $$.label + " = " + $1.label + " <= " + $3.label + ";\n";
    }
    | E TK_MAIOR_IGUAL E
    {
        $$.label = gentempcode();
        $$.tipo = "bool";
        vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao +
                      "\t" + $$.label + " = " + $1.label + " >= " + $3.label + ";\n";
    }
	
    /* PARENTESIS (Agrupamento matemático) */
    | '(' E ')'
    {
        $$.label = $2.label;
        $$.tipo = $2.tipo;
        $$.traducao = $2.traducao;
    }
    
    /* CONVERSÃO EXPLÍCITA (CAST: ex: (int) 3.5 ) */
    | '(' tipo ')' E
    {
        $$.label = gentempcode();
        $$.tipo = $2.tipo; /* O novo tipo vai ser o que está dentro do parênteses */
        
        /* Declara o temporário com o novo tipo lá no topo */
        vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";
        
        /* Imprime a conversão no código C */
        $$.traducao = $4.traducao +
                      "\t" + $$.label + " = (" + $2.tipo + ") " + $4.label + ";\n";
    }

    /* VALORES LITERAIS */
    | TK_NUM
    {
        if ($1.tipo == "char") {
            /* Se for caractere, passa direto sem gerar temporário extra */
            $$.label = $1.label;
            $$.tipo = $1.tipo;
            $$.traducao = "";
        } else {
            /* Mantém a regra normal para int e float (Testes 03 e 05) */
            $$.label = gentempcode();
            $$.tipo = $1.tipo;
            vars_temporarias += "\t" + $1.tipo + " " + $$.label + ";\n";
            $$.traducao = "\t" + $$.label + " = " + $1.label + ";\n";
        }
    }
    | TK_TRUE
    {
        /* Booleano passa direto como 1 sem temporário */
        $$.label = "1";
        $$.tipo = "int";
        $$.traducao = "";
    }
    | TK_FALSE
    {
        /* Booleano passa direto como 0 sem temporário */
        $$.label = "0";
        $$.tipo = "int";
        $$.traducao = "";
    }
    
    /* VARIÁVEL */
    /* VARIÁVEL DENTRO DA CONTA */
    | TK_ID
    {
        Variavel* v = buscarVariavel($1.label);
        if (v) {
            /* Variável foi declarada antes (int A;), então usamos o rótulo interno dela (t1) */
            $$.label = v->label;
            $$.tipo = v->tipo;
            $$.traducao = "";
        } else {
            /* Variável não declarada (apareceu do nada), gera a leitura tX = A;*/
            $$.label = gentempcode();
            $$.tipo = "int";
            vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";
            $$.traducao = "\t" + $$.label + " = " + $1.label + ";\n";
        }
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
