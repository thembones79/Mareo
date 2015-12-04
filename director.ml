open Sprite
open Object
open Actors

type keys = {
  mutable left: bool;
  mutable right: bool;
  mutable up: bool;
  mutable down: bool;
}

type viewport = {
  pos: Object.xy;
  v_dim: Object.xy;
  m_dim: Object.xy;
}

type st = {
  bgd: sprite;
  ctx: Dom_html.canvasRenderingContext2D Js.t;
  vpt: viewport;
  mutable score: int;
  mutable coins: int;
  mutable multiplier: int;
}

let make_viewport (vx,vy) (mx,my) =
  {
    pos = {x = 0.; y = 0.;};
    v_dim = {x = vx; y = vy};
    m_dim = {x = mx; y = my};
  }

let calc_viewport_point cc vc mc =
  let vc_half = vc /. 2. in
  min ( max (cc -. vc_half) 0. ) ( min (mc -. vc) (abs_float(cc -. vc_half)) )

let in_viewport v pos =
  let margin = 32. in
  let (v_min_x,v_max_x) = (v.pos.x -. margin, v.pos.x +. v.v_dim.x) in
  let (v_min_y,v_max_y) = (v.pos.y -. margin, v.pos.y +. v.v_dim.y) in
  let (x,y) = (pos.x, pos.y) in
  let test = x >= v_min_x && x <= v_max_x && y >= v_min_y && y<= v_max_y in
  test

let coord_to_viewport viewport coord =
  {
    x = coord.x -. viewport.pos.x;
    y = coord.y -. viewport.pos.y;
  }

let update_viewport vpt ctr =
  let new_x = calc_viewport_point ctr.x vpt.v_dim.x vpt.m_dim.x in
  let new_y = calc_viewport_point ctr.y vpt.v_dim.y vpt.m_dim.y in
  let pos = {x = new_x; y = new_y} in
  {vpt with pos}

let pressed_keys = {
  left = false;
  right = false;
  up = false;
  down = false;
}

let collid_objs = ref []
let last_time = ref 0.

let end_game () =
  Dom_html.window##alert (Js.string "Game over!");
  failwith "Game over."

let calc_fps t0 t1 =
  let delta = (t1 -. t0) /. 1000. in
  1. /. delta

let update_score state i =
  state.score <- state.score + i

let player_attack_enemy s1 o1 typ s2 o2 state context =
  o1.invuln <- invuln;
  o1.jumping <- false;
  o1.grounded <- true;
  Printf.printf "Multiplier: %d \n" state.multiplier;
  Printf.printf "Score: %d \n" state.score;
  begin match typ with
  | GKoopaShell | RKoopaShell ->
      let r2 = evolve_enemy o1.dir typ s2 o2 context in
      o1.vel.y <- ~-. dampen_jump;
      o1.pos.y <- o1.pos.y -. 5.;
      (None,r2)
  | _ ->
      dec_health o2;
      o1.invuln <- invuln;
      o1.vel.y <- ~-. dampen_jump;
      ( if state.multiplier = 16 then ( update_score state 1600; (None, evolve_enemy o1.dir typ s2 o2 context) )
         else ( update_score state (100 * state.multiplier);
              state.multiplier <- state.multiplier * 2;
      (None,(evolve_enemy o1.dir typ s2 o2 context)) ))
  end

let enemy_attack_player s1 o1 t2 s2 o2 context =
  o1.invuln <- invuln;
  begin match t2 with
  | GKoopaShell |RKoopaShell ->
      let r2 = if o2.vel.x = 0. then evolve_enemy o1.dir t2 s2 o2 context
              else (dec_health o1; None) in
      (None,r2)
  | _ -> dec_health o1; (None,None)
  end

let col_enemy_enemy t1 s1 o1 t2 s2 o2 dir =
  begin match (t1, t2) with
  | (GKoopaShell, GKoopaShell)
  | (GKoopaShell, RKoopaShell)
  | (RKoopaShell, RKoopaShell)
  | (RKoopaShell, GKoopaShell) ->
      dec_health o1;
      dec_health o2;
      (None,None)
  | (RKoopaShell, _) | (GKoopaShell, _) -> if o1.vel.x = 0. then
      (rev_dir o2 t2 s2;
      (None,None) )
      else ( dec_health o2; (None,None) )
  | (_, RKoopaShell) | (_, GKoopaShell) -> if o2.vel.x = 0. then
      (rev_dir o1 t1 s1;
      (None,None) )
      else ( dec_health o1; (None,None) )
  | (_, _) ->
      begin match dir with
      | West | East ->
          rev_dir o1 t1 s1;
          rev_dir o2 t2 s2;
          (None,None)
      | _ -> (None,None)
      end
  end

let process_collision dir c1 c2  state =
  let context = state.ctx in
  match (c1, c2, dir) with
  | (Player(_,s1,o1), Enemy(typ,s2,o2), South)
  | (Enemy(typ,s2,o2),Player(_,s1,o1), North) ->
      player_attack_enemy s1 o1 typ s2 o2 state context
  | (Player(_,s1,o1), Enemy(t2,s2,o2), _)
  | (Enemy(t2,s2,o2), Player(_,s1,o1), _) ->
      enemy_attack_player s1 o1 t2 s2 o2 context
  | (Player(_,s1,o1), Item(t2,s2,o2), _)
  | (Item(t2,s2,o2), Player(_,s1,o1), _) ->
      begin match t2 with
      | Mushroom -> dec_health o2; o1.health <- o1.health + 1; (None, None)
      | Coin -> state.coins <- state.coins + 1; dec_health o2;
          Printf.printf "Coins: %d \n" state.coins; (None, None)
      | _ -> dec_health o2; (None, None)
      end
  | (Enemy(t1,s1,o1), Enemy(t2,s2,o2), dir) ->
      col_enemy_enemy t1 s1 o1 t2 s2 o2 dir
  | (Enemy(t,s1,o1), Block(typ2,s2,o2), East)
  | (Enemy(t,s1,o1), Block(typ2,s2,o2), West)->
    begin match (t,typ2) with
    | (RKoopaShell, Brick) | (GKoopaShell, Brick) ->
        dec_health o2;
        reverse_left_right o1;
        (None,None)
    (*TODO: spawn item when block is of type qblock*)
    | (_,_) ->
        rev_dir o1 t s1;
      (None,None)
    end
  | (Item(_,s1,o1), Block(typ2,s2,o2), East)
  | (Item(_,s1,o1), Block(typ2,s2,o2), West) ->
      reverse_left_right o1;
      (None, None)
  | (Enemy(_,s1,o1), Block(typ2,s2,o2), _)
  | (Item(_,s1,o1), Block(typ2,s2,o2), _) ->
      collide_block dir o1;
      (None, None)
  | (Player(_,s1,o1), Block(t,s2,o2), North) ->
      begin match t with
      | QBlock typ ->
          let updated_block = evolve_block o2 context in
          let spawned_item = spawn_above o1.dir o2 typ context in
          collide_block dir o1;
          (Some spawned_item, Some updated_block)
      | Brick -> collide_block dir o1; dec_health o2; (None, None)
      | _ -> collide_block dir o1; (None,None)
      end
  | (Player(_,s1,o1), Block(t,s2,o2), _) ->
    begin match dir with
    | South -> state.multiplier <- 0 ; collide_block dir o1; (None, None)
    | _ -> collide_block dir o1; (None, None)
    end
  | (_, _, _) -> (None,None)

let broad_cache = ref []
let broad_phase collid =
  !broad_cache

let rec narrow_phase c cs state =
  let rec narrow_helper c cs state acc =
    match cs with
    | [] -> acc
    | h::t ->
      let c_obj = get_obj c in
      let invuln = c_obj.invuln in
      let new_objs = if not (equals c h) && invuln <= 0 then
        begin match Object.check_collision c h with
        | None -> (None,None)
        | Some dir ->
          if (get_obj h).id <> c_obj.id
          then process_collision dir c h state
          else (None,None)
      end else (None,None) in
      let acc = match new_objs with
        | (None, Some o) -> o::acc
        | (Some o, None) -> o::acc
        | (Some o1, Some o2) -> o1::o2::acc
        | (None, None) -> acc
      in
      c_obj.invuln <- if invuln > 0 then invuln-1 else invuln;
      narrow_helper c t state acc
  in narrow_helper c cs state []

let check_collisions collid state =
  match collid with
  | Block(_,_,_) -> []
  | _ ->
    let broad = broad_phase collid in
    narrow_phase collid broad state

let update_collidable state (collid:Object.collidable) all_collids =
 (* TODO: optimize. Draw static elements only once *)
  let obj = Object.get_obj collid in
  let spr = Object.get_sprite collid in
  if not obj.kill && (in_viewport state.vpt obj.pos || is_player collid) then begin
    obj.grounded <- false;
    Object.process_obj obj;
    (* Run collision detection if moving object*)
    let evolved = check_collisions collid state in
    (* Render and update animation *)
    let vpt_adj_xy = coord_to_viewport state.vpt obj.pos in
    Draw.render spr (vpt_adj_xy.x,vpt_adj_xy.y);
    if obj.vel.x <> 0. || not (is_enemy collid) then Sprite.update_animation spr;
    evolved
  end else []

let translate_keys () =
  let k = pressed_keys in
  let ctrls = [(k.left,CLeft);(k.right,CRight);(k.up,CUp);(k.down,CDown)] in
  List.fold_left (fun a x -> if fst x then (snd x)::a else a) [] ctrls

let run_update state collid all_collids =
  match collid with
  | Player(t,s,o) as p ->
      let keys = translate_keys () in
      let player = begin match Object.update_player o keys state.ctx with
        | None -> p
        | Some (new_typ, new_spr) -> Player(new_typ,new_spr,o)
      end in
      let evolved = update_collidable state player all_collids in
      collid_objs := !collid_objs @ evolved;
      player
  | _ ->
      let obj = get_obj collid in
      let evolved = update_collidable state collid all_collids in
      if not obj.kill then (collid_objs := collid::(!collid_objs@evolved));
      collid

let update_loop canvas objs =
  let ctx = canvas##getContext (Dom_html._2d_) in
  let cwidth = float_of_int canvas##width in
  let cheight = float_of_int canvas##height in
  let viewport = make_viewport (cwidth,cheight) (cwidth +. 500.,cheight +. 500.) in
  let player = Object.spawn (SPlayer(SmallM,Standing)) ctx (200.,32.) in
  let state = {
      bgd = Sprite.make_bgd ctx;
      vpt = update_viewport viewport (get_obj player).pos;
      ctx;
      score = 0;
      coins = 0;
      multiplier = 1;
  } in
  let rec update_helper time state player objs  =
      collid_objs := [];

      let fps = calc_fps !last_time time in
      last_time := time;

      broad_cache := objs;

      Draw.clear_canvas canvas;

      (* Parallax background *)
      let vpos_x_int = int_of_float (state.vpt.pos.x /. 5.)  in
      let bgd_width = int_of_float (fst state.bgd.params.frame_size) in
      Draw.draw_bgd state.bgd (float_of_int (vpos_x_int mod bgd_width));

      let player = run_update state player objs in
      let state = {state with vpt = update_viewport state.vpt (get_obj player).pos} in
      List.iter (fun obj -> ignore (run_update state obj objs)) objs ;

      Draw.fps canvas fps;
      ignore Dom_html.window##requestAnimationFrame(
          Js.wrap_callback (fun (t:float) -> update_helper t state player !collid_objs))

  in update_helper 0. state player objs

let keydown evt =
  let () = match evt##keyCode with
  | 38 | 32 -> pressed_keys.up <- true; print_endline  "Jump"
  | 39 -> pressed_keys.right <- true; print_endline "Right"
  | 37 -> pressed_keys.left <- true; print_endline "Left"
  | 40 -> pressed_keys.down <- true; print_endline "Crouch"
  | _ -> ()
  in Js._true

let keyup evt =
  let () = match evt##keyCode with
  | 38 | 32 -> pressed_keys.up <- false
  | 39 -> pressed_keys.right <- false
  | 37 -> pressed_keys.left <- false
  | 40 -> pressed_keys.down <- false
  | _ -> ()
  in Js._true
