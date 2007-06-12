%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include "tree.h"
#include "sl2c.h"

/* ---------------------------------------------------------------------------
 *
 * Notes.
 *
 *   Usually, shader code is small compared to other languages(C/C++, etc).
 *   Thus I use basic data structure(doubly-linked list, linear search, etc)
 *   and don't use efficient data structure(hash, binary search, etc).
 *
 * ------------------------------------------------------------------------ */

/*
 * List of nodes
 */
typedef struct _node_list_t
{
	node_t               *expr;
	
	/*
	 * Doubly-linked list
	 */
	struct _node_list_t  *next;
	struct _node_list_t  *prev;

} node_list_t;

typedef struct _stmt_block_t
{

	node_list_t          *node_list;

	int                   depth;
	int                   type;


} stmt_block_t;

typedef struct _stmt_block_list_t
{
	stmt_block_t               *block;

	/*
	 * Doubly-linked list.
	 */
	struct _stmt_block_list_t  *next;
	struct _stmt_block_list_t  *prev;

} stmt_block_list_t;

typedef struct _function_t
{
	stmt_block_list_t    *stmt_block_list;

	//int             currblockdepth;

	node_list_t          *expr_list;
	node_list_t          *formal_expr_list;

#if 0	/* to be removed */
	int             nexpr;
	int             nformalexpr;
	int             nscalarexpr;
#endif

	char                 *func_name;

} function_t;

typedef struct _function_list_t
{
	function_t *func;

	/*
	 * Doubly-linked list.
	 */
	struct _function_list_t *next;
	struct _function_list_t *prev;

} function_list_t;

/*
 * Abstract syntax tree
 */
typedef struct _ast_t
{
	function_list_t *func_list;

} ast_t;


/* ---------------------------------------------------------------------------
 *
 * Defines
 *
 * ------------------------------------------------------------------------ */

#define BLOCK_BEGIN      1
#define BLOCK_END        2

/*
 * gcc specific.
 */
#define SL2C_DEBUG(fmt, ...) { \
	if (g_debug) { \
		printf("%s:%d " fmt, __FUNCTION__, __LINE__, ## __VA_ARGS__); \
	} \
}
 
/* ---------------------------------------------------------------------------
 *
 * Globals
 *
 * ------------------------------------------------------------------------ */

/* defined in sl2c.c */
extern char sl2c_verstr[];
extern char sl2c_datestr[]; 
extern char sl2c_progname[]; 


int g_debug = 1;

ast_t       ast;		/* global singletion	*/


// TODO: to be removed
//func_body_t f;			/* gloal singleton */
function_t  *curr_func;		/* ptr to current function */
stmt_block_t      *curr_stmt_block;      /* ptr to current statement block */
stmt_block_list_t *curr_stmt_block_list; /* ptr to current statement block list */
node_list_t *curr_node_list;	/* ptr to current node list */

static int vartype;		/* type of variable */

extern int nlines;		/* defined in lexsl.l */
int        get_parsed_line();

void	   yyerror(char *s);

static void emit_header();
static void emit_function(function_t *func);
static void emit_block(stmt_block_t *block);
static void emit_func_arg();
static void emit_param_initializer(const function_t *func);

static void init_function(char *func_name);

static node_list_t *
append_node(node_list_t *node_list, node_t *node)
{
	node_list_t *new_list = (node_list_t *)malloc(sizeof(node_list_t));
	assert(new_list);

	new_list->expr = node;

	if (node_list != NULL) {

		new_list->prev = node_list;
		new_list->next = NULL;

		node_list->next = new_list;

	} else {

		new_list->prev = NULL;
		new_list->next = NULL;
	}

	return new_list;
}

static function_list_t *
append_function(function_list_t *func_list, function_t *func)
{
	function_list_t *new_list = (function_list_t *)malloc(
					sizeof(function_list_t));
	assert(new_list);

	new_list->func = func;

	if (func_list != NULL) {

		new_list->prev = func_list;
		new_list->next = NULL;

		func_list->next = new_list;

	} else {

		new_list->prev = NULL;
		new_list->next = NULL;
	}

	return new_list;
}

static stmt_block_t *
new_stmt_block()
{
	stmt_block_t *new_stmt = (stmt_block_t *)malloc(sizeof(stmt_block_t));
	assert(new_stmt);

	new_stmt->node_list = NULL;

	return new_stmt;
}

static stmt_block_list_t *
append_stmt_block(stmt_block_list_t *stmt_block_list, stmt_block_t *block)
{
	stmt_block_list_t *new_list = (stmt_block_list_t *)malloc(
					sizeof(stmt_block_list_t));
	assert(new_list);

	new_list->block = block;

	if (stmt_block_list != NULL) {

		new_list->prev = stmt_block_list;
		new_list->next = NULL;

		stmt_block_list->next = new_list;

	} else {

		new_list->prev = NULL;
		new_list->next = NULL;
	}

	return new_list;
}


static void
emit_header()
{
	fprintf(g_csfp, "/*				\n");
	fprintf(g_csfp, " * Generated by %s. (version %s)	\n",
		sl2c_progname, sl2c_verstr);
	fprintf(g_csfp, " */				\n");
	fprintf(g_csfp, "\n");
	fprintf(g_csfp, "#include <stdio.h>\n");
	fprintf(g_csfp, "#include <stdlib.h>\n");
	fprintf(g_csfp, "#include <math.h>\n");
	fprintf(g_csfp, "\n");
	fprintf(g_csfp, "#include \"shader.h\"\n");
	fprintf(g_csfp, "\n");
}

static void
emit_function(function_t *func)
{
	sym_t *sp;

	// TODO:
	return;

	fprintf(g_csfp, "DLLEXPORT void\n");
	fprintf(g_csfp, "%s", func->func_name);
	emit_func_arg();
	fprintf(g_csfp, "{\n");

	
			
	/*
	 * Write list of formal variable definiton.
	 */
	{
		node_list_t *formal_expr_list;

		formal_expr_list = func->formal_expr_list;
		while (formal_expr_list != NULL) {

			emit_defvar(formal_expr_list->expr);

			formal_expr_list = formal_expr_list->next;
		}

		fprintf(g_csfp, "\n");
	}


	/*
	 * Write list of variable definition.
	 */
	{

		node_list_t *expr_list;

		expr_list = func->expr_list;
		while (expr_list != NULL) {

			emit_defvar(expr_list->expr);

			expr_list = expr_list->next;
		}

		fprintf(g_csfp, "\n");
	}

	/*
	 * Write param initializer code.
 	 */
	{
		node_list_t *expr_list;

		expr_list = func->formal_expr_list;

		while (expr_list != NULL) {

			if (expr_list->expr->opcode != OP_VARDEF) continue;


			sp = (sym_t *)expr_list->expr->left->left;

			fprintf(g_csfp,
				"\tri_param_eval(&%s, param, \"%s\");\n",
				sp->name, sp->name);

			expr_list = expr_list->next;
		}

		fprintf(g_csfp, "\n");
	}

	/*
	 * Write expressions
	 */
	{
		node_list_t  *expr_list;
		node_t       *expr;

		while (expr_list != NULL) {

			expr = expr_list->expr;

			if (expr->opcode == OP_FOR   ||
			    expr->opcode == OP_WHILE ||
			    expr->opcode == OP_IF    ||
			    expr->opcode == OP_ILLUMINANCE) {

				// TODO:
				//emit_block(&i);

			} else if (expr->type == FLOAT) {

				if (expr->opcode == OP_VARDEF &&
				    !expr->right) {

					/*
					 * do nothing
					 */

				} else {

					emit_scalar_node(expr);
					fprintf(g_csfp, ";\n");

				}

			} else {

				emit_node(expr);

			}

			expr_list = expr_list->next;
		}
	}

	fprintf(g_csfp, "}\n");
}

static void
emit_stmt(stmt_block_t *stmt)
{
	(void)stmt;
#if 0 // TODO: implement
	int i, indent;
	int start, end;
	int elsestart, elseend;

#if 0
	start     = expr_list->start;
	end       = expr_list->end;
	elsestart = expr_list->elsestart;
	elseend   = expr_list->elseend;
#endif

	indent = stmt->depth;

	set_indent(indent);

	emit_scalar_node(expr_list->expr);
	fprintf(g_csfp, "\n");

	i = start;
	while (i <= end) {
		if (expr_list->expr->opcode == OP_FOR   ||
		    expr_list->expr->opcode == OP_WHILE ||
		    expr_list->expr->opcode == OP_IF    ||
		    expr_list->expr->opcode == OP_ILLUMINANCE) {
			emit_block(&i);
		} else if (expr_list->expr->type == FLOAT) {
			set_indent(indent + 1);
			emit_scalar_node(exprlist->expr);
			fprintf(g_csfp, ";\n");
		} else {
			set_indent(indent + 1);
			emit_node(f.exprlist[i].expr);
		}

		i++;
	}

	set_indent(indent);
	emit_indent();
	fprintf(g_csfp, "\t}");

	if (elseend != 0) {
		fprintf(g_csfp, " else {\n");
		i = elsestart;
		while (i <= elseend) {
			if (f.exprlist[i].expr->opcode == OP_FOR   ||
			    f.exprlist[i].expr->opcode == OP_WHILE ||
			    f.exprlist[i].expr->opcode == OP_IF    ||
			    f.exprlist[i].expr->opcode == OP_ILLUMINANCE) {
				emit_block(&i);
			} else if (f.exprlist[i].expr->type == FLOAT) {
				set_indent(indent + 1);
				emit_scalar_node(f.exprlist[i].expr);
				fprintf(g_csfp, ";\n");
			} else {
				set_indent(indent + 1);
				emit_node(f.exprlist[i].expr);
			}

			i++;
		}

		set_indent(indent);
		emit_indent();
		fprintf(g_csfp, "\t}");
	}

	fprintf(g_csfp, "\n");
	set_indent(indent);

	if (elseend == 0) {
		*curr = end;
	} else {
		*curr = elseend;
	}
#endif

}

static void
emit_func_arg()
{
	fprintf(g_csfp, "(ri_output_t *output, ");
	fprintf(g_csfp, "ri_status_t *status, ");
	fprintf(g_csfp, "ri_parameter_t *param)\n");
}

static void
emit_param_initializer(const function_t *func)
{
	//int i;
	//sym_t *sp;
	//char buf[256];

	fprintf(g_csfp, "DLLEXPORT void\n");
	fprintf(g_csfp, "%s_initparam(ri_parameter_t *param)\n",
			func->func_name);
	fprintf(g_csfp, "{\n");

#if 0	// TODO: implement
	for (i = 0; i < f.nformalexpr; i++) {
		emit_tmpvar(f.formalexprlist[i]);
	}

	fprintf(g_csfp, "\n");

	for (i = 0; i < f.nformalexpr; i++) {
		if (f.formalexprlist[i]->type == FLOAT) {
			emit_scalar_node(f.formalexprlist[i]);
			fprintf(g_csfp, ";\n");
		} else {
			emit_node(f.formalexprlist[i]);
		}
	}

	fprintf(g_csfp, "\n");

	for (i = 0; i < f.nformalexpr; i++) {
		if (f.formalexprlist[i]->opcode != OP_VARDEF) continue;

		sp = (sym_t *)f.formalexprlist[i]->left->left;

		switch(sp->type) {
		case FLOAT:
			strcpy(buf, "TYPEFLOAT");
			
			break;

		case VECTOR:
		case COLOR:
		case POINT:
			strcpy(buf, "TYPEVECTOR");
			if (!f.formalexprlist[i]->right) {
				/* set default value. */
				fprintf(g_csfp, "\tri_vector_set(%s", sp->name);
				fprintf(g_csfp, ", 0.0, 0.0, 0.0, 1.0);\n");
			}

			break;

		case STRING:
			strcpy(buf, "TYPESTRING");
			if (!f.formalexprlist[i]->right) {
				/* set default value. */
				fprintf(g_csfp, "\t%s = "";\n", sp->name);
			}

			break;

		default:
			strcpy(buf, "TYPEUNKNOWN");
			break;
		}

		if (sp->type == FLOAT) {
			fprintf(g_csfp, "\tri_param_add(param, \"%s\", %s, &%s);\n",
				sp->name, buf, sp->name);
		} else {
			fprintf(g_csfp, "\tri_param_add(param, \"%s\", %s, &%s);\n",
				sp->name, buf, sp->name);
		}

	}
#endif
	fprintf(g_csfp, "}\n");
}

/*
 * Initialize Abstract Syntax Tree.
 */
void
init_ast()
{
	SL2C_DEBUG("init_ast()\n");

	ast.func_list = NULL;
}

void
init_function(char *func_name)
{
	//static int first = 1;

	SL2C_DEBUG("Enter function def: %s\n", func_name);

	curr_func = (function_t *)malloc(sizeof(function_t));
	assert(curr_func);
	curr_func->func_name = strdup(func_name);

#if 0	// TODO: implement
	if (first) {
		f.blocks = (block_t *)malloc(sizeof(block_t));
		f.blocks->prev = NULL;
		first = 0;

	} else {
		while ((f.blocks = pop_block(f.blocks)) != NULL);

		free(f.func_name);
	}

	f.nexpr          = 0;
	f.nformalexpr    = 0; 
	f.nscalarexpr    = 0;

	f.func_name	 = strdup(func_name);
#endif

}

%}

%union {
	char   *string;
	node_t *np;
	double  fval;
	int     ival;
}

%token SURFACE
%token <string> IDENTIFIER
%token <fval> NUMBER
%token <string> STRINGCONSTANT
%token VOID FLOAT NORMAL VECTOR COLOR POINT STRING LIGHTSOURCE
%token VARYING UNIFORM
%token ENVIRONMENT
%token TEXTURE
%token RADIANS DEGREES
%token ABS FLOOR CEIL ROUND MIX MOD NOISE STEP SMOOTHSTEP SQRT INVERSESQRT
%token LENGTH
%token SIN ASIN COS ACOS TAN ATAN
%token POW EXP LOG SIGN
%token RANDOM
%token MATH_PI
%token REFRACT
%token OCCLUSION TRACE
%token AMBIENT DIFFUSE SPECULAR TEXTURE ENVIRONMENT
%token PLUSEQ MINUSEQ MULEQ
%token XCOMP YCOMP ZCOMP
%token SETXCOMP SETYCOMP SETZCOMP
%token TRIPLE
%token AREA
%token FOR WHILE IF ELSE
%token ILLUMINANCE
%token OP_NULL
%token OP_ASSIGN OP_VARDEF OP_DEFEXPR OP_FORMAL_DEFEXPR
%token OP_MUL OP_DIV OP_DOT OP_ADD OP_SUB OP_NEG
%token OP_FUNC OP_FUNCARG OP_FUNC_HEADER OP_CALLFUNC
%token OP_ASSIGNADD OP_ASSIGNSUB OP_ASSIGNMUL OP_COND OP_COND_TRIPLE
%token OP_PARENT
%token OP_LE OP_GE OP_EQ OP_NEQ
%token OP_FTOV
%token OP_FOR OP_FORCOND OP_WHILE OP_IF OP_ILLUMINANCE OP_IF_ELSE
%token OP_STMT

%right '=' PLUSEQ MINUSEQ MULEQ
%left '<'
%left '+' '-'
%left '*' '/'
%left '.'
%left UMINUS /* unary minus */ TYPECAST

%type <np> statement statements
%type <np> assignexpression expression primary triple
%type <np> def_expression def_init
%type <np> procedurecall proc_arguments
%type <np> texture texture_type texture_arguments
%type <np> loop_control relation
%type <np> variable_definitions variable_def_expressions
%type <np> typespec
%type <np> formals formal_def_expressions formal_variable_definitions 
%type <np> func_head function
%type <np> block

%type <ival> type

%%

/* --- declarations --- */

definitions		:
			{
				init_ast();
				emit_header();
			} funclist
;

funclist		: /* empty */
			| funclist function
;

function		: func_head block
			{
				
				SL2C_DEBUG("Leave func def\n");

				$$ = make_node(OP_FUNC, 2, $1, $2);
	
				dump_node($$);

#if 0	// TODO
				emit_param_initializer(curr_func);

				fprintf(g_csfp, "\n");
			
				emit_function(curr_func);

				ast.func_list = append_function(
					ast.func_list, curr_func);
#endif
			}
;

func_head		: type IDENTIFIER '(' formals ')'
			{
				var_reg($2, $1);

				$$ = make_node(OP_FUNC_HEADER,
					       2,
					       make_leaf($2),
					       $4);

			}
;

formals			: /* empty */
			{
				// TODO
				$$ = make_node(OP_NULL, 0);
			}
			| formal_variable_definitions
			{
				// TODO
				$$ = $1;
			}
			| formals ';' formal_variable_definitions
			{
				// TODO
				$$ = make_node(OP_VARDEF, 2, $1, $3);
			}
			| formals ';'
			{
				// TODO
				$$ = $1;
			}
;


formal_variable_definitions : typespec formal_def_expressions
			{
				$$ = $2;
			}
;

variable_definitions	: typespec variable_def_expressions
			{
				$$ = $2;
			}
;

typespec		: detail type
			{
			}
;

type			: FLOAT
			{
				vartype = FLOAT;
				$$ = FLOAT;
			}
			| NORMAL
			{
				vartype = NORMAL;
				$$ = NORMAL;
			}
			| VECTOR
			{
				vartype = VECTOR;
				$$ = VECTOR;
			}
			| COLOR
			{
				vartype = COLOR;
				$$ = COLOR;
			}
			| POINT
			{
				vartype = POINT;
				$$ = POINT;
			}
			| STRING
			{
				vartype = STRING;
				$$ = STRING;
			}
			| SURFACE
			{
				vartype = SURFACE;
				$$ = SURFACE;
			}
;

detail			: /* empty */
			| VARYING
			{
				/* do nothing */
			}
			| UNIFORM
			{
				/* do nothing */
			}

formal_def_expressions	: def_expression
			{
				SL2C_DEBUG("formal_def\n");
				
				$$ = make_node(OP_DEFEXPR,
					       2,
					       $1,
					       make_node(OP_NULL, 0));

	
			}
			| formal_def_expressions ',' def_expression
			{
				SL2C_DEBUG("formal_def, \n");

				$$ = make_node(OP_DEFEXPR, 2, $1, $3);

			}
;

variable_def_expressions : def_expression
			{
				SL2C_DEBUG("def_expr\n");

				$$ = make_node(OP_DEFEXPR,
					       2,
					       $1,
					       make_node(OP_NULL, 0));

			}
			| variable_def_expressions ',' def_expression
			{
				SL2C_DEBUG("def_expr,\n");

				$$ = make_node(OP_DEFEXPR, 2, $1, $3);

			}
;

def_expression	: IDENTIFIER def_init
			{
				var_reg($1, vartype);
				
				$$ = make_node(OP_VARDEF,
				     2,
				     make_leaf($1),
				     $2);
			}
;


def_init		: /* empty */
			{
				$$ = make_node(OP_NULL, 0);
			}
			| '=' expression
			{
				$$ = $2;
			}
;

/* --------------------------------------------------------------------------
 *
 * statements 
 *
 * ----------------------------------------------------------------------- */

block			: '{' statements '}'
			{
				$$ = $2;
			}
;	

statements		: /* empty */
			{
				$$ = make_node(OP_NULL, 0);
			}
			| statements statement
			{
				$$ = make_node(OP_STMT, 2, $1, $2);
			}
;

statement		: ';'
			{
				printf("make ';'\n");
				$$ = make_node(OP_NULL, 0);
			}	
			| variable_definitions ';'
			{
				SL2C_DEBUG("variable_def ';'\n");
				$$ = $1;
			}
			| assignexpression ';' 
			{
				SL2C_DEBUG("statement\n");

				$$ = $1;

			}
			| '{' statements '}'
			{
				$$ = $2;
			}
			| loop_control statement
			{
				// TODO

			}
			| IF '(' relation ')' statement
			{
				// TODO
				SL2C_DEBUG("if relation stmt\n");

			}
			| IF '(' relation ')' statement ELSE statement
			{
				SL2C_DEBUG("if ELSE statement\n");

				$$ = make_node(OP_IF_ELSE, 3, $3, $5, $7);

			}
;

loop_control		: FOR '(' expression ';' relation ';' expression ')'
			{
				// TODO;
			}
			| WHILE '(' relation ')'
			{
				// TODO;
			}
			| ILLUMINANCE '(' expression ',' expression ',' expression ')'
			{
				// TODO;
			}
;

relation		: expression '<' expression
			{
				$$ = make_node(OP_LE, 2, $1, $3);
			}
			| expression '>' expression
			{
				$$ = make_node(OP_GE, 2, $1, $3);
			}
			| expression OP_EQ expression
			{
				$$ = make_node(OP_EQ, 2, $1, $3);
			}
			| expression OP_NEQ expression
			{
				$$ = make_node(OP_NEQ, 2, $1, $3);
			}
;

/* --------------------------------------------------------------------------
 *
 * expressions
 *
 * ----------------------------------------------------------------------- */

expression		: primary
			{
				$$ = $1;
			}
			| expression '+' expression
			{
				$$ = make_node(OP_ADD, 2, $1, $3);
			}
			| expression '-' expression
			{
				$$ = make_node(OP_SUB, 2, $1, $3);
			}
			| expression '*' expression
			{
				$$ = make_node(OP_MUL, 2, $1, $3);
				emit_node($$);
			}
			| expression '/' expression
			{
				$$ = make_node(OP_DIV, 2, $1, $3);
			}
			| expression '.' expression
			{
				$$ = make_node(OP_DOT, 2, $1, $3);
				$$->type = FLOAT;
			}
			| '-' expression %prec UMINUS
			{
				$$ = make_node(OP_NEG, 1, $2);
			}
			| relation '?' expression ':' expression
			{
				$$ = make_node(OP_COND_TRIPLE, 3, $1, $3, $5);
				$$->type = FLOAT;
			}
			| '(' expression ')'
			{
				$$ = make_node(OP_PARENT, 1, $2);
			}
			| typecast expression %prec TYPECAST
			{
				$$ = $2;
			}
;

primary			: NUMBER
			{
				$$ = make_constnum($1);
			}
			| MATH_PI
			{
				$$ = make_constnum(3.141593);
			}
			| STRINGCONSTANT
			{
				var_reg($1, vartype);
				$$ = make_conststr($1);
			}
			| IDENTIFIER
			{
				var_reg($1, vartype);
				$$ = make_leaf($1);
			}
			| texture
			{
			}
			| procedurecall
			{
			}
			| assignexpression
			{
			}
			| triple
			{
				$$ = $1;
			}
;

triple			: '(' expression ',' expression ',' expression ')'
			{
				$$ = make_node(TRIPLE, 3, $2, $4, $6);
			}

spacetype		: /* empty */
			| STRINGCONSTANT
			{
			}
;

typecast		: COLOR spacetype
;


assignexpression	: IDENTIFIER '=' expression
			{
				var_reg($1, vartype);
				$$ = make_node(OP_ASSIGN, 
					       2,
					       make_leaf($1),
					       $3);
			}
			| IDENTIFIER PLUSEQ expression
			{
				var_reg($1, vartype);
				$$ = make_node(OP_ASSIGNADD, 
					       2,
					       make_leaf($1),
					       $3);
			}
			| IDENTIFIER MINUSEQ expression
			{
				var_reg($1, vartype);
				$$ = make_node(OP_ASSIGNSUB, 
					       2,
					       make_leaf($1),
					       $3);
			}
			| IDENTIFIER MULEQ expression
			{
				var_reg($1, vartype);
				$$ = make_node(OP_ASSIGNMUL, 
					       2,
					       make_leaf($1),
					       $3);
			}
;


procedurecall		: RADIANS '(' proc_arguments ')'
			{
				$$ = make_node(RADIANS, 1, $3);
			}
			| DEGREES '(' proc_arguments ')'
			{
				$$ = make_node(DEGREES, 1, $3);
			}
			| ABS '(' proc_arguments ')'
			{
				$$ = make_node(ABS, 1, $3);
			}
			| SIN '(' proc_arguments ')'
			{
				$$ = make_node(SIN, 1, $3);
			}
			| ASIN '(' proc_arguments ')'
			{
				$$ = make_node(ASIN, 1, $3);
			}
			| COS '(' proc_arguments ')'
			{
				$$ = make_node(COS, 1, $3);
			}
			| ACOS '(' proc_arguments ')'
			{
				$$ = make_node(ACOS, 1, $3);
			}
			| TAN '(' proc_arguments ')'
			{
				$$ = make_node(TAN, 1, $3);
			}
			| ATAN '(' proc_arguments ')'
			{
				$$ = make_node(ATAN, 1, $3);
			}
			| POW '(' proc_arguments ')'
			{
				$$ = make_node(POW, 1, $3);
			}
			| EXP '(' proc_arguments ')'
			{
				$$ = make_node(EXP, 1, $3);
			}
			| LOG '(' proc_arguments ')'
			{
				$$ = make_node(LOG, 1, $3);
			}
			| SIGN '(' proc_arguments ')'
			{
				$$ = make_node(SIGN, 1, $3);
			}
			| RANDOM '(' ')'
			{
				$$ = make_node(RANDOM, 0);
			}
			| FLOOR '(' proc_arguments ')'
			{
				$$ = make_node(FLOOR, 1, $3);
			}
			| CEIL '(' proc_arguments ')'
			{
				$$ = make_node(CEIL, 1, $3);
			}
			| ROUND '(' proc_arguments ')'
			{
				$$ = make_node(ROUND, 1, $3);
			}
			| MIX '(' proc_arguments ')'
			{
				$$ = make_node(MIX, 1, $3);	
				if ($3) {
					$$->type = $3->type;
				}
			}
			| REFRACT '(' proc_arguments ')'
			{
				$$ = make_node(REFRACT, 1, $3);	
			}
			| MOD '(' proc_arguments ')'
			{
				$$ = make_node(MOD, 1, $3);	
			}
			| NOISE '(' proc_arguments ')'
			{
				$$ = make_node(NOISE, 1, $3);	
				$$->type = FLOAT;
			}
			| LENGTH '(' proc_arguments ')'
			{
				$$ = make_node(LENGTH, 1, $3);	
				$$->type = FLOAT;
			}
			| AMBIENT '(' proc_arguments ')'
			{
				$$ = make_node(AMBIENT, 1, $3);	
			}
			| DIFFUSE '(' proc_arguments ')'
			{
				$$ = make_node(DIFFUSE, 1, $3);	
			}
			| SPECULAR '(' proc_arguments ')'
			{
				$$ = make_node(SPECULAR, 1, $3);	
			}
			| ENVIRONMENT '(' proc_arguments ')'
			{
				$$ = make_node(ENVIRONMENT, 1, $3);	
			}
			/* TODO */
			/*
			| TEXTURE '(' proc_arguments ')'
			{
				$$ = make_node(TEXTURE, 1, $3);	
				$$->type = COLOR;
			}
			*/
			| OCCLUSION '(' proc_arguments ')'
			{
				$$ = make_node(OCCLUSION, 1, $3);	
				$$->type = FLOAT;
			}
			| TRACE '(' proc_arguments ')'
			{
				$$ = make_node(TRACE, 1, $3);	
			}
			| STEP '(' proc_arguments ')'
			{
				$$ = make_node(STEP, 1, $3);	
				$$->type = FLOAT;
			}
			| SMOOTHSTEP '(' proc_arguments ')'
			{
				$$ = make_node(SMOOTHSTEP, 1, $3);	
				$$->type = FLOAT;
			}
			| SQRT '(' proc_arguments ')'
			{
				$$ = make_node(SQRT, 1, $3);
			}
			| INVERSESQRT '(' proc_arguments ')'
			{
				$$ = make_node(INVERSESQRT, 1, $3);
			}
			| XCOMP '(' proc_arguments ')'
			{
				$$ = make_node(XCOMP, 1, $3);
				$$->type = FLOAT;
			}
			| YCOMP '(' proc_arguments ')'
			{
				$$ = make_node(YCOMP, 1, $3);
				$$->type = FLOAT;
			}
			| ZCOMP '(' proc_arguments ')'
			{
				$$ = make_node(ZCOMP, 1, $3);
				$$->type = FLOAT;
			}
			| SETXCOMP '(' proc_arguments ')'
			{
				$$ = make_node(SETXCOMP, 1, $3);
				$$->type = VOID;
			}
			| SETYCOMP '(' proc_arguments ')'
			{
				$$ = make_node(SETYCOMP, 1, $3);
				$$->type = VOID;
			}
			| SETZCOMP '(' proc_arguments ')'
			{
				$$ = make_node(SETZCOMP, 1, $3);
				$$->type = VOID;
			}
			| AREA '(' proc_arguments ')'
			{
				$$ = make_node(AREA, 1, $3);
				$$->type = FLOAT;
			}
			| IDENTIFIER '(' proc_arguments ')'
			{
				var_reg($1, VECTOR);
				$$ = make_node(OP_CALLFUNC,
					       2,
					       make_leaf($1),
					       $3);
			}
;

proc_arguments		: /* empty */
			{
				$$ = NULL;
			}
			| expression
			{
				$$ = make_node(OP_FUNCARG,
					       1,
					       $1);
				//$$ = $1;
			}
			| expression ',' proc_arguments
			{
				$$ = make_node(OP_FUNCARG,
					       2,
					       $1,
					       $3);
			}
;

texture			: texture_type
			  '(' texture_arguments ')'
			{
				$$ = make_node(TEXTURE,
					       2,
					       $1,
					       $3);
				//$$->type = COLOR;

			}
;

texture_type		: ENVIRONMENT
			{
				char *tex = "environment";
				var_reg(tex, COLOR);

				$$ = make_leaf(tex);
			}
			| TEXTURE
			{
				char *tex = "texture";
				var_reg(tex, COLOR);

				$$ = make_leaf(tex);
			}
;

texture_arguments	: expression
			{
				$$ = make_node(OP_FUNCARG,
					       1,
					       $1);
			}
			| expression ',' texture_arguments
			{
				$$ = make_node(OP_FUNCARG,
					       2,
					       $1,
					       $3);
			}
;

%%

#if 0
int
main(int argc, char **argv)
{
	extern FILE *yyin;
	extern int yydebug;

	if (argc < 2) {
		printf("usage: %s file.sl\n", argv[0]);
		exit(-1);
	}

	yyin = fopen(argv[1], "r");

	//yydebug = 1;

	yyparse();

	return 0;
}
#endif

int
get_parsed_line()
{
	return nlines;
}

void
yyerror(char *s)
{
	fprintf(stderr, "Parse error: %s at line %d\n", s, nlines);
}

