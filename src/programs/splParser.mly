%{
open Programs
open Form
open SplSyntax
open Lexing


(* let parse_error =  ParseError.parse_error *)

let mk_position s e =
  let start_pos = Parsing.rhs_start_pos s in
  let end_pos = Parsing.rhs_end_pos e in
  { sp_file = start_pos.pos_fname;
    sp_start_line = start_pos.pos_lnum;
    sp_start_col = start_pos.pos_cnum - start_pos.pos_bol;
    sp_end_line = end_pos.pos_lnum;
    sp_end_col = end_pos.pos_cnum - end_pos.pos_bol;
  } 

%}

%token <string> IDENT
%token <int> INTVAL
%token <bool> BOOLVAL
%token LPAREN RPAREN LBRACE RBRACE
%token COLON COLONEQ SEMICOLON DOT PIPE
%token UMINUS PLUS MINUS DIV TIMES
%token EQ NEQ LEQ GEQ LT GT
%token PTS EMP NULL
%token SEP AND OR NOT COMMA
%token ASSUME ASSERT CALL NEW DISPOSE RETURN
%token IF ELSE WHILE
%token GHOST VAR STRUCT PROCEDURE PREDICATE
%token RETURNS REQUIRES ENSURES INVARIANT
%token INT BOOL
%token EOF

%nonassoc COLONEQ 
%nonassoc ASSUME ASSERT
%nonassoc NEW DISPOSE

%left SEMICOLON
%left OR
%left AND
%left SEP
%left DOT
%right NOT
%nonassoc LT GT LEQ GEQ
%nonassoc EQ NEQ 
%nonassoc PTS LS
%left PLUS MINUS
%left TIMES DIV
%nonassoc LPAREN

%start main
%type <SplSyntax.compilation_unit> main
%%

main:
| declarations {
  compilation_unit None [] $1
} 
;

declarations:
  proc_decl declarations 
  { ProcDecl $1 :: $2 }
|   pred_decl declarations 
  { PredDecl $1 :: $2 }
| struct_decl declarations
  { StructDecl $1 :: $2 }
| var_decl declarations
  { VarDecl $1 :: $2 }
| /* empty */ { [] }
| error { ProgError.syntax_error (mk_position 1 1) }
;


proc_decl:
| proc_header proc_impl {
  proc_decl $1 $2
} 
;

proc_header:
| PROCEDURE IDENT LPAREN var_decls RPAREN proc_returns proc_contracts {  
  let formals, locals0 =
    List.fold_right (fun decl (formals, locals0) ->
      decl.v_name :: formals, IdMap.add decl.v_name decl locals0)
      $4 ([], IdMap.empty)
  in
  let returns, locals =
    List.fold_right (fun decl (returns, locals) ->
      decl.v_name :: returns, IdMap.add decl.v_name decl locals)
      $6 ([], locals0)
  in
  let decl = 
    { p_name = ($2, 0);
      p_formals = formals;  
      p_returns = returns; 
      p_locals = locals;
      p_contracts = $7;
      p_body = Skip; 
      p_pos = mk_position 2 2;
    }
  in 
  decl
} 
;

proc_contracts:
| proc_contract proc_contracts { $1 :: $2 }
| /* empty */ { [] }
;

proc_contract:
| REQUIRES expr SEMICOLON { Requires $2 }
| ENSURES expr SEMICOLON { Ensures $2 }

proc_impl:
| SEMICOLON { Skip }
| LBRACE block RBRACE { Block ($2, mk_position 1 3) }
;

pred_decl:
| PREDICATE IDENT LPAREN var_decls RPAREN LBRACE expr RBRACE {
  let formals, locals =
    List.fold_right (fun decl (formals, locals) ->
      decl.v_name :: formals, IdMap.add decl.v_name decl locals)
      $4 ([], IdMap.empty)
  in
  let decl =
    { pr_name = ($2, 0);
      pr_formals = formals;
      pr_locals = locals;
      pr_body = $7;
      pr_pos = mk_position 2 2;
    }
  in decl
} 


var_decls:
| var_decl var_decl_list { $1 :: $2 }
| /* empty */ { [] }
;

var_decl_list:
| COMMA var_decl var_decls { $2 :: $3 }
| /* empty */ { [] }
;

var_decl:
| var_modifier IDENT COLON var_type { 
  let decl = 
    { v_name = ($2, 0);
      v_type = $4;
      v_ghost = $1;
      v_aux = false;
      v_pos = mk_position 2 2;
    } 
  in
  decl
}
;

var_modifier:
| GHOST { true }
| /* empty */ { false }
; 

var_type:
| INT { IntType }
| BOOL { BoolType }
| IDENT { StructType ($1, 0) }
;

proc_returns:
| RETURNS LPAREN var_decls RPAREN { $3 }
| /* empty */ { [] }
;

struct_decl:
| STRUCT IDENT LBRACE field_decls RBRACE {
  let fields =
    List.fold_left (fun fields decl->
      IdMap.add decl.v_name decl fields)
      IdMap.empty $4
  in
  let decl = 
    { s_name = ($2, 0);
      s_fields = fields;
      s_pos = mk_position 2 2;
    } 
  in
  decl
} 
;

field_decls:
| field_decl field_decls { $1 :: $2 }
| /* empty */ { [] }

field_decl:
| VAR var_decl SEMICOLON { $2 }


block:
  stmt block { $1 :: $2 }
| /* empty */ { [] }
;

stmt:
/* variable declaration */
| VAR var_decls SEMICOLON { LocalVars ($2, mk_position 1 3) }
/* nested block */
| LBRACE block RBRACE { 
  Block ($2, mk_position 1 3) 
}
/* deallocation */
| DISPOSE expr SEMICOLON { 
  Dispose ($2, mk_position 1 3)
}
/* assignment */
| expr_list COLONEQ expr_list SEMICOLON {
  Assign ($1, $3, mk_position 1 4)
}
/* assume */
| ASSUME expr SEMICOLON {
  Assume ($2, mk_position 1 3)
}
/* assert */
| ASSERT expr SEMICOLON { 
  Assert ($2, mk_position 1 3)
}
/* if-then-else */
| IF LPAREN expr RPAREN stmt ELSE stmt { 
  If ($3, $5, $7, mk_position 1 7)
}
/* if-then 
| IF LPAREN expr RPAREN stmt  { 
  If ($3, $5, Skip, mk_position 1 6)
}*/
/* while loop */
| WHILE LPAREN expr RPAREN loop_contracts stmt {
  Loop ($5, Skip, $3, $6, mk_position 1 6)
} 
/* return */
| RETURN expr_opt SEMICOLON { 
  Return ($2, mk_position 1 3)
}
;

loop_contracts:
| loop_contract loop_contracts { $1 :: $2 }
| /* empty */ { [] }
;
loop_contract:
| INVARIANT expr SEMICOLON { Invariant $2 }
;

primary:
| INTVAL { IntVal ($1, mk_position 1 1) }
| BOOLVAL { BoolVal ($1, mk_position 1 1) }
| NULL { Null (mk_position 1 1) }
| EMP { Emp (mk_position 1 1) }
| LPAREN expr RPAREN { $2 }
| alloc { $1 }
| proc_call { $1 }
;

alloc:
| NEW IDENT { New (($2, 0), mk_position 1 2) }

proc_call:
| IDENT LPAREN expr_list_opt RPAREN { Call (($1, 0), $3, mk_position 1 4) }


unary_expr:
| primary { $1 }
| unary_expr DOT IDENT { Dot ($1, ($3, 0), mk_position 1 3) }
| IDENT { Ident (($1, 0), mk_position 1 1) }
| PLUS unary_expr { UnaryOp (OpPlus, $2, mk_position 1 2) }
| MINUS unary_expr { UnaryOp (OpMinus, $2, mk_position 1 2) }
| PIPE unary_expr PIPE { UnaryOp (OpDomain, $2, mk_position 1 3) }
| unary_expr_not_plus_minus { $1 }
;

unary_expr_not_plus_minus:
| NOT unary_expr  { UnaryOp (OpNot, $2, mk_position 1 2) }
;

mult_expr:
| unary_expr  { $1 }
| mult_expr TIMES unary_expr { BinaryOp ($1, OpMult, $3, mk_position 1 3) }
| mult_expr DIV unary_expr { BinaryOp ($1, OpDiv, $3, mk_position 1 3) }

add_expr:
| mult_expr { $1 }
| add_expr PLUS add_expr { BinaryOp ($1, OpPlus, $3, mk_position 1 3) }
| add_expr MINUS add_expr { BinaryOp ($1, OpMinus, $3, mk_position 1 3) }

pts_expr:
| add_expr { $1 }
| pts_expr PTS add_expr { BinaryOp ($1, OpPts, $3, mk_position 1 3) }


rel_expr:
| pts_expr { $1 }
| rel_expr LT pts_expr { BinaryOp ($1, OpLt, $3, mk_position 1 3) }
| rel_expr GT pts_expr { BinaryOp ($1, OpGt, $3, mk_position 1 3) }
| rel_expr LEQ pts_expr { BinaryOp ($1, OpLeq, $3, mk_position 1 3) }
| rel_expr GEQ pts_expr { BinaryOp ($1, OpGeq, $3, mk_position 1 3) }

eq_expr:
| rel_expr { $1 }
| eq_expr EQ rel_expr { BinaryOp ($1, OpEq, $3, mk_position 1 3) }
| eq_expr NEQ rel_expr { BinaryOp ($1, OpNeq, $3, mk_position 1 3) }

sep_expr:
| eq_expr { $1 }
| sep_expr SEP eq_expr { BinaryOp ($1, OpSep, $3, mk_position 1 3) }

and_expr:
| sep_expr { $1 }
| and_expr AND sep_expr { BinaryOp ($1, OpAnd, $3, mk_position 1 3) }

or_expr:
| and_expr { $1 }
| or_expr OR and_expr { BinaryOp ($1, OpOr, $3, mk_position 1 3) }

expr:
| or_expr { $1 } 
;

expr_opt:
| expr { Some $1 } 
| /* empty */ { None }
;

expr_list_opt:
| expr_list { $1 }
| /* empty */ { [] }
;

expr_list:
| expr COMMA expr_list { $1 :: $3 }
| expr { [$1] }
;
