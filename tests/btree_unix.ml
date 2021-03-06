module T = Dbtlk_types 

let do_read_op fd {T.offset; length} = 
  ignore @@ Unix.lseek fd offset Unix.SEEK_SET; 
  let bytes = Bytes.create length in 
  begin match Unix.read fd bytes 0 length with
  |  nb_of_bytes when nb_of_bytes = length -> () 
  | _ -> failwith "read incomplete"
  end;
  bytes

let do_write_op fd {T.offset; bytes; } = 
  ignore @@ Unix.lseek fd offset Unix.SEEK_SET; 
  let length = Bytes.length bytes in 
  begin match Unix.write fd bytes 0 length with
  | nb_of_bytes when nb_of_bytes = length -> () 
  | _ -> failwith "write incomplete"
  end

let int_compare (x:int) (y:int) = Pervasives.compare x y 

let do_write_ops fd write_ops = 
  List.sort (fun {T.offset = lhs; _} {T.offset = rhs; _} -> 
    int_compare lhs rhs
  ) write_ops
  |>  List.iter (fun write -> do_write_op fd write)

let do_allocate fd length = 
  let offset = Unix.lseek fd 0 Unix.SEEK_END in 
  let write_op = {
    T.offset; 
    bytes = Bytes.make length (char_of_int 0)
  } in 
  do_write_op fd write_op; 
  offset

let rec do_res fd = function  
  | T.Res_done x -> x 
  | T.Res_read_data (block, k) -> 
    do_read_op fd block |> k |> do_res fd 
  | T.Res_allocate (block_length, k) ->
    do_allocate fd block_length |> k  |>  do_res fd 

module Make (Key:Dbtlk_btree.Key_sig) (Val:Dbtlk_btree.Val_sig) = struct 

  module Internal = Dbtlk_btree.Make(Key)(Val)

  type t = {
    fd : Unix.file_descr; 
    root_offset: int;
    m : int;
  }

  
  let make ~filename ~m () = 
    let node = Internal.make ~root_file_offset:0 ~m () in 
    let write_op = Internal.initialize node in 
    let fd = Unix.openfile filename [Unix.O_RDWR; Unix.O_CREAT] 0o640 in 
    do_write_op fd write_op; 
    {fd; root_offset = 0; m}

  let node_on_disk {root_offset; m; _} = 
    Internal.make ~root_file_offset:root_offset ~m () 
    
  let insert_aux ({fd;_} as t) res = 
    match do_res fd res with
    | Internal.Insert_res_done (root_offset, write_ops) -> begin  
      do_write_ops fd write_ops;
      match root_offset with
      | None -> t 
      | Some root_offset -> {t with root_offset} 
    end 
    | Internal.Insert_res_node_split _ -> assert(false)

  let insert t key value = 
    Internal.insert (node_on_disk t) key value |> insert_aux t 
  
  let append t key value = 
    Internal.append (node_on_disk t) key value |> insert_aux t 

  let debug ({fd; _} as t)= 
    Internal.debug (node_on_disk t) |> do_res fd 

  let find ({fd; _} as t)key = 
    Internal.find (node_on_disk t) key |> do_res fd 

  let iter ({fd; _} as t) f = 
    Internal.iter (node_on_disk t) f |> do_res fd 

end (* Make *) 
