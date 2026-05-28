%{
#include <iostream>
#include <string>
#include <stdio.h>
#include <map>
#include <stack>
#include <cstdlib>

#define YYSTYPE atributos
using namespace std;

int var_temp_qnt;
string codigo_gerado;
string vars_temporarias = ""; 

extern int linha;

struct atributos {
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
        if (copia.top().count(nome)) return &copia.top()[nome];
        copia.pop();
    }
    return nullptr;
}

string tipoResultante(string t1, string t2) {
    if (t1 == "bool" || t2 == "bool") return "erro";
    if (t1 == "char" || t2 == "char") return "erro"; 
    
    if (t1 == t2) return t1;
    if ((t1 == "float" && t2 == "int") ||
        (t1 == "int"   && t2 == "float")) return "float";
        
    return "erro";
}

void erroSemantico(string msg) {
    cerr << "Erro Semantico na linha " << linha << ": " << msg << endl;
    exit(1); 
}

string gentempcode(); 

struct Cast {
    string label;
    string traducao;
};

Cast gerarCast(string label, string tipoOriginal, string tipoDestino) {
    Cast c;
    c.label = label;
    c.traducao = "";
    if (tipoOriginal == "int" && tipoDestino == "float") {
        c.label = gentempcode();
        vars_temporarias += "\tfloat " + c.label + ";\n";
        c.traducao = "\t" + c.label + " = (float) " + label + ";\n";
    }
    return c;
}

int yylex(void);
void yyerror(string);

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
%token TK_PRINT
%token TK_READ

/* Precedencia Java */
%left TK_OU
%left TK_E
%left TK_IGUAL TK_DIFERENTE
%left '<' '>' TK_MENOR_IGUAL TK_MAIOR_IGUAL
%left '+' '-'
%left '*' '/'
%right TK_NAO

%start S

%%

S
    : lista_comandos
    {
        codigo_gerado = "__________________________\n\n"
                        "★  MIKU COMPILER (^_^)  ★\n"
                        "__________________________\n\n"
                        "#include <stdio.h>\n"
                        "int main(void) {\n";
                        
        codigo_gerado += vars_temporarias; 
        codigo_gerado += "\n";
        codigo_gerado += $1.traducao;
        
        codigo_gerado += "\treturn 0;\n";
        codigo_gerado += "}\n";
    }
    ;

lista_comandos
    : lista_comandos comando { $$.traducao = $1.traducao + $2.traducao; }
    |                        { $$.traducao = ""; }
    ;

comando
    : declaracao             { $$.traducao = $1.traducao; }
    | atribuicao             { $$.traducao = $1.traducao; }
    | E ';'                  { $$.traducao = $1.traducao; }
    | Bloco                  { $$.traducao = $1.traducao; }
    | TK_PRINT '(' E ')' ';'
    {
        string fmt;
        if ($3.tipo == "int" || $3.tipo == "bool") fmt = "%d";
        else if ($3.tipo == "float") fmt = "%f";
        else if ($3.tipo == "char") fmt = "%c";
        
        $$.traducao = $3.traducao + "\tprintf(\"" + fmt + "\\n\", " + $3.label + ");\n";
    }
    | TK_READ '(' TK_ID ')' ';'
    {
        Variavel* v = buscarVariavel($3.label);
        if (!v) erroSemantico("Variavel '" + $3.label + "' nao declarada.");
        
        string fmt;
        if (v->tipo == "int" || v->tipo == "bool") fmt = "%d";
        else if (v->tipo == "float") fmt = "%f";
        else if (v->tipo == "char") fmt = "%c";
        
        $$.traducao = "\tscanf(\"" + fmt + "\", &" + v->label + ");\n";
    }
    ;

Bloco
    : '{' { entrarEscopo(); } lista_comandos '}'
    {
        $$.traducao = "\t{\n" + $3.traducao + "\t}\n";
        sairEscopo();
    }
    ;

tipo
    : TK_TIPO_INT   { $$.tipo = "int";   $$.label = "int"; }
    | TK_TIPO_FLOAT { $$.tipo = "float"; $$.label = "float"; }
    | TK_TIPO_BOOL  { $$.tipo = "bool";  $$.label = "int"; }
    | TK_TIPO_CHAR  { $$.tipo = "char";  $$.label = "char"; }
    ;

declaracao
    : tipo TK_ID ';'
    {
        string varLabel = gentempcode(); 
        declararVariavel($2.label, $1.tipo, varLabel);
        vars_temporarias += "\t" + $1.label + " " + varLabel + ";\n"; 
        $$.traducao = "";
    }
    | tipo TK_ID TK_ATRIB E ';'
    {
        string varLabel = gentempcode(); 
        declararVariavel($2.label, $1.tipo, varLabel);
        vars_temporarias += "\t" + $1.label + " " + varLabel + ";\n";
        
        string traducaoAux = $4.traducao;
        string labelOrigemFinal = $4.label;

        if ($1.tipo == "int" && $4.tipo == "float") erroSemantico("Nao eh possivel inicializar int com float.");
        else if ($1.tipo == "float" && $4.tipo == "int") {
            Cast c = gerarCast($4.label, "int", "float");
            traducaoAux += c.traducao;
            labelOrigemFinal = c.label;
        }
        else if ($1.tipo != $4.tipo) erroSemantico("Tipos incompativeis.");

        $$.traducao = traducaoAux + "\t" + varLabel + " = " + labelOrigemFinal + ";\n";
    }
    ;

atribuicao
    : TK_ID TK_ATRIB E ';'
    {
        Variavel* v = buscarVariavel($1.label);
        if (!v) erroSemantico("Variavel '" + $1.label + "' nao declarada.");
        
        string traducaoAux = $3.traducao;
        string labelOrigemFinal = $3.label;

        if (v->tipo == "int" && $3.tipo == "float") erroSemantico("Nao eh possivel atribuir float para int.");
        else if (v->tipo == "float" && $3.tipo == "int") {
            Cast c = gerarCast($3.label, "int", "float");
            traducaoAux += c.traducao;
            labelOrigemFinal = c.label;
        }
        else if (v->tipo != $3.tipo) erroSemantico("Tipos incompativeis na atribuicao.");

        $$.traducao = traducaoAux + "\t" + v->label + " = " + labelOrigemFinal + ";\n";
    }
    ;

E
    : E '+' E
    {
        $$.tipo = tipoResultante($1.tipo, $3.tipo);
        if ($$.tipo == "erro") erroSemantico("Operacao '+' invalida.");
        Cast c1 = gerarCast($1.label, $1.tipo, $$.tipo);
        Cast c3 = gerarCast($3.label, $3.tipo, $$.tipo);
        $$.label = gentempcode();
        vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";
        $$.traducao = $1.traducao + c1.traducao + $3.traducao + c3.traducao + "\t" + $$.label + " = " + c1.label + " + " + c3.label + ";\n";
    }
    | E '-' E
    {
        $$.tipo = tipoResultante($1.tipo, $3.tipo);
        if ($$.tipo == "erro") erroSemantico("Operacao '-' invalida.");
        Cast c1 = gerarCast($1.label, $1.tipo, $$.tipo);
        Cast c3 = gerarCast($3.label, $3.tipo, $$.tipo);
        $$.label = gentempcode();
        vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";
        $$.traducao = $1.traducao + c1.traducao + $3.traducao + c3.traducao + "\t" + $$.label + " = " + c1.label + " - " + c3.label + ";\n";
    }
    | E '*' E
    {
        $$.tipo = tipoResultante($1.tipo, $3.tipo);
        if ($$.tipo == "erro") erroSemantico("Operacao '*' invalida.");
        Cast c1 = gerarCast($1.label, $1.tipo, $$.tipo);
        Cast c3 = gerarCast($3.label, $3.tipo, $$.tipo);
        $$.label = gentempcode();
        vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";
        $$.traducao = $1.traducao + c1.traducao + $3.traducao + c3.traducao + "\t" + $$.label + " = " + c1.label + " * " + c3.label + ";\n";
    }
    | E '/' E
    {
        $$.tipo = tipoResultante($1.tipo, $3.tipo);
        if ($$.tipo == "erro") erroSemantico("Operacao '/' invalida.");
        Cast c1 = gerarCast($1.label, $1.tipo, $$.tipo);
        Cast c3 = gerarCast($3.label, $3.tipo, $$.tipo);
        $$.label = gentempcode();
        vars_temporarias += "\t" + $$.tipo + " " + $$.label + ";\n";
        $$.traducao = $1.traducao + c1.traducao + $3.traducao + c3.traducao + "\t" + $$.label + " = " + c1.label + " / " + c3.label + ";\n";
    }
    | E TK_E E
    {
        if ($1.tipo != "bool" || $3.tipo != "bool") erroSemantico("Operador '&&' exige bool.");
        $$.label = gentempcode(); $$.tipo = "bool"; vars_temporarias += "\tint " + $$.label + ";\n"; 
        $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " && " + $3.label + ";\n";
    }
    | E TK_OU E
    {
        if ($1.tipo != "bool" || $3.tipo != "bool") erroSemantico("Operador '||' exige bool.");
        $$.label = gentempcode(); $$.tipo = "bool"; vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " || " + $3.label + ";\n";
    }
    | TK_NAO E
    {
        if ($2.tipo != "bool") erroSemantico("Operador '!' exige bool.");
        $$.label = gentempcode(); $$.tipo = "bool"; vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $2.traducao + "\t" + $$.label + " = !" + $2.label + ";\n";
    }
    | E TK_IGUAL E
    {
        $$.label = gentempcode(); $$.tipo = "bool"; vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " == " + $3.label + ";\n";
    }
    | E TK_DIFERENTE E
    {
        $$.label = gentempcode(); $$.tipo = "bool"; vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " != " + $3.label + ";\n";
    }
    | E '<' E
    {
        $$.label = gentempcode(); $$.tipo = "bool"; vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " < " + $3.label + ";\n";
    }
    | E '>' E
    {
        $$.label = gentempcode(); $$.tipo = "bool"; vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " > " + $3.label + ";\n";
    }
    | E TK_MENOR_IGUAL E
    {
        $$.label = gentempcode(); $$.tipo = "bool"; vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " <= " + $3.label + ";\n";
    }
    | E TK_MAIOR_IGUAL E
    {
        $$.label = gentempcode(); $$.tipo = "bool"; vars_temporarias += "\tint " + $$.label + ";\n";
        $$.traducao = $1.traducao + $3.traducao + "\t" + $$.label + " = " + $1.label + " >= " + $3.label + ";\n";
    }
    | '(' E ')' { $$.label = $2.label; $$.tipo = $2.tipo; $$.traducao = $2.traducao; }
    | '(' tipo ')' E
    {
        $$.label = gentempcode(); $$.tipo = $2.tipo; vars_temporarias += "\t" + $2.label + " " + $$.label + ";\n"; 
        $$.traducao = $4.traducao + "\t" + $$.label + " = (" + $2.label + ") " + $4.label + ";\n";
    }
    | TK_NUM
    {
        if ($1.tipo == "char") { $$.label = $1.label; $$.tipo = $1.tipo; $$.traducao = ""; }
        else { $$.label = gentempcode(); $$.tipo = $1.tipo; vars_temporarias += "\t" + $1.tipo + " " + $$.label + ";\n"; $$.traducao = "\t" + $$.label + " = " + $1.label + ";\n"; }
    }
    | TK_TRUE { $$.label = "1"; $$.tipo = "bool"; $$.traducao = ""; }
    | TK_FALSE { $$.label = "0"; $$.tipo = "bool"; $$.traducao = ""; }
    | TK_ID
    {
        Variavel* v = buscarVariavel($1.label);
        if (v) { $$.label = v->label; $$.tipo = v->tipo; $$.traducao = ""; }
        else { erroSemantico("Variavel '" + $1.label + "' nao declarada."); }
    }
    ;

%%

string gentempcode() { var_temp_qnt++; return "t" + to_string(var_temp_qnt); }

int main(int argc, char* argv[])
{
    var_temp_qnt = 0;
    entrarEscopo();
    if (argc > 1) { yyin = fopen(argv[1], "r"); }
    if (yyparse() == 0) cout << codigo_gerado;
    sairEscopo();
    return 0;
}

void yyerror(string MSG)
{
    cerr << "Erro Sintatico na linha " << linha << ": " << MSG << endl;
}