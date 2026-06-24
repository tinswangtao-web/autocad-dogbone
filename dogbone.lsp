;;; dogbone.lsp
;;; AutoCAD for Mac compatible AutoLISP dogbone helper.
;;; Stable version: V2.1
;;;
;;; Commands:
;;;   DBSET   - Set tool diameter and whether contained hole outlines are handled.
;;;   DB1     - Draw A/B/C single-corner test geometry for review.
;;;   DBDEBUG - Draw debug markers for recognized dogbone corners.
;;;   DBADD   - Add dogbones to selected sharp corners.
;;;   DBRESTORE - Restore selected dogbones back to sharp corners.
;;;   DBRESTOREALL - Restore all dogbones in selected polylines.
;;;   DBAUTO  - Rebuild selected closed LWPOLYLINE entities or 1:1 block definitions
;;;             with C 45-degree dogbones.
;;;   DBNSET  - Set nesting gap (minimum spacing between parts, default 6 mm).
;;;   DBNEST  - Pack selected parts into a rectangular sheet with AABB nesting.
;;;   DBNESTM - Pack selected parts across copied sheet frames.
;;;
;;; Production mode creates a new closed LWPOLYLINE and deletes the original
;;; only after the replacement entity is created successfully.

(setq *db-version* "V2.1-Nest")
(setq *db-tool-dia* 6.0)
(setq *db-layer* "DOGBONE")
(setq *db-process-holes* T)
(setq *db-preview* nil)
(setq *db-dogbone-type* "C")
(setq *db-duplicate-tol* 0.01)
(setq *db-angle90-tol* 0.1)
(setq *db-keep-original* nil)
(setq *db-debug-mode* nil)
(setq *db-restore-bulge-tol* 0.05)
(setq *db-eps* 1.0e-8)
(setq *db-nest-gap* 6.0)
(setq *db-nest-sheet-gap* 50.0)

(defun db:ensure-defaults ()
  (if (not *db-tool-dia*) (setq *db-tool-dia* 6.0))
  (if (not *db-layer*) (setq *db-layer* "DOGBONE"))
  (if (not *db-process-holes*) (setq *db-process-holes* nil))
  (if (not *db-preview*) (setq *db-preview* nil))
  (if (not *db-dogbone-type*) (setq *db-dogbone-type* "C"))
  (if (not *db-duplicate-tol*) (setq *db-duplicate-tol* 0.01))
  (if (not *db-angle90-tol*) (setq *db-angle90-tol* 0.1))
  (if (not (boundp '*db-keep-original*)) (setq *db-keep-original* nil))
  (if (not (boundp '*db-debug-mode*)) (setq *db-debug-mode* nil))
  (if (not *db-restore-bulge-tol*) (setq *db-restore-bulge-tol* 0.05))
  (if (not *db-eps*) (setq *db-eps* 1.0e-8))
  (if (not *db-nest-gap*) (setq *db-nest-gap* 6.0))
  (if (not *db-nest-sheet-gap*) (setq *db-nest-sheet-gap* 50.0))
)

(defun db:radius ()
  (/ *db-tool-dia* 2.0)
)

(defun db:bool-text (v)
  (if v "Yes" "No")
)

(defun db:pt2 (p)
  (list (float (car p)) (float (cadr p)) 0.0)
)

(defun db:x (p) (car p))
(defun db:y (p) (cadr p))

(defun db:add (a b)
  (list (+ (db:x a) (db:x b)) (+ (db:y a) (db:y b)) 0.0)
)

(defun db:sub (a b)
  (list (- (db:x a) (db:x b)) (- (db:y a) (db:y b)) 0.0)
)

(defun db:mul (a s)
  (list (* (db:x a) s) (* (db:y a) s) 0.0)
)

(defun db:dot (a b)
  (+ (* (db:x a) (db:x b)) (* (db:y a) (db:y b)))
)

(defun db:crossz (a b)
  (- (* (db:x a) (db:y b)) (* (db:y a) (db:x b)))
)

(defun db:len (a)
  (sqrt (db:dot a a))
)

(defun db:norm (a / l)
  (setq l (db:len a))
  (if (< l *db-eps*)
    nil
    (db:mul a (/ 1.0 l))
  )
)

(defun db:clamp (x lo hi)
  (cond
    ((< x lo) lo)
    ((> x hi) hi)
    (T x)
  )
)

(defun db:acos (x)
  (setq x (db:clamp x -1.0 1.0))
  (atan (sqrt (max 0.0 (- 1.0 (* x x)))) x)
)

(defun db:rad->deg (a)
  (/ (* a 180.0) pi)
)

(defun db:tan (a)
  (/ (sin a) (cos a))
)

(defun db:distance (a b)
  (db:len (db:sub a b))
)

(defun db:pick-tolerance ()
  (max 2.0 (* (db:radius) 2.0))
)

(defun db:pt2d (p)
  (list (float (car p)) (float (cadr p)))
)

(defun db:rect-from-points (a b)
  (list
    (min (db:x a) (db:x b))
    (min (db:y a) (db:y b))
    (max (db:x a) (db:x b))
    (max (db:y a) (db:y b))
  )
)

(defun db:point-in-rect (pt rect)
  (and
    (>= (db:x pt) (nth 0 rect))
    (<= (db:x pt) (nth 2 rect))
    (>= (db:y pt) (nth 1 rect))
    (<= (db:y pt) (nth 3 rect))
  )
)

(defun db:min-distance-to-points (pt pts / best p d)
  (setq best nil)
  (foreach p pts
    (setq d (db:distance pt p))
    (if (or (not best) (< d best))
      (setq best d)
    )
  )
  best
)

(defun db:list-has-int (value values / found v)
  (setq found nil)
  (foreach v values
    (if (= value v)
      (setq found T)
    )
  )
  found
)

(defun db:assoc-value (key alist default / found)
  (setq found (assoc key alist))
  (if found (cdr found) default)
)

(defun db:ensure-layer (/ layer-def)
  (if (not (tblsearch "LAYER" *db-layer*))
    (progn
      (setq layer-def
        (list
          '(0 . "LAYER")
          '(100 . "AcDbSymbolTableRecord")
          '(100 . "AcDbLayerTableRecord")
          (cons 2 *db-layer*)
          '(70 . 0)
          '(62 . 1)
          '(6 . "Continuous")
        )
      )
      (entmake layer-def)
    )
  )
)

(defun db:ensure-named-layer (name color / layer-def)
  (if (not (tblsearch "LAYER" name))
    (progn
      (setq layer-def
        (list
          '(0 . "LAYER")
          '(100 . "AcDbSymbolTableRecord")
          '(100 . "AcDbLayerTableRecord")
          (cons 2 name)
          '(70 . 0)
          (cons 62 color)
          '(6 . "Continuous")
        )
      )
      (entmake layer-def)
    )
  )
)

(defun db:angle (p)
  (atan (db:y p) (db:x p))
)

(defun db:signed-angle (a b / ang)
  (setq ang (- (db:angle b) (db:angle a)))
  (while (> ang pi)
    (setq ang (- ang (* 2.0 pi)))
  )
  (while (< ang (- pi))
    (setq ang (+ ang (* 2.0 pi)))
  )
  ang
)

(defun db:point-on-circle (center radius angle)
  (list
    (+ (db:x center) (* radius (cos angle)))
    (+ (db:y center) (* radius (sin angle)))
    0.0
  )
)

(defun db:arc-bulge-near-corner (center radius start end corner / a1 a2 ang alt mid1 mid2 d1 d2 chosen)
  (setq a1 (db:angle (db:sub start center)))
  (setq a2 (db:angle (db:sub end center)))
  (setq ang (db:signed-angle (db:sub start center) (db:sub end center)))
  (setq alt (if (> ang 0.0) (- ang (* 2.0 pi)) (+ ang (* 2.0 pi))))
  (setq mid1 (db:point-on-circle center radius (+ a1 (/ ang 2.0))))
  (setq mid2 (db:point-on-circle center radius (+ a1 (/ alt 2.0))))
  (setq d1 (db:distance mid1 corner))
  (setq d2 (db:distance mid2 corner))
  (setq chosen (if (< d1 d2) ang alt))
  (db:tan (/ chosen 4.0))
)

(defun db:make-circle-on-layer (layer center radius)
  (entmakex
    (list
      '(0 . "CIRCLE")
      (cons 8 layer)
      (cons 10 (db:pt2 center))
      (cons 40 radius)
    )
  )
)

(defun db:make-line-on-layer (layer p1 p2)
  (entmakex
    (list
      '(0 . "LINE")
      (cons 8 layer)
      (cons 10 (db:pt2 p1))
      (cons 11 (db:pt2 p2))
    )
  )
)

(defun db:make-point-on-layer (layer pt)
  (entmakex
    (list
      '(0 . "POINT")
      (cons 8 layer)
      (cons 10 (db:pt2 pt))
    )
  )
)

(defun db:make-text-on-layer (layer pt height text)
  (entmakex
    (list
      '(0 . "TEXT")
      (cons 8 layer)
      (cons 10 (db:pt2 pt))
      (cons 40 height)
      (cons 1 text)
      '(50 . 0.0)
      '(72 . 0)
      '(73 . 0)
    )
  )
)

(defun db:make-lwpolyline-owned (owner layer color ltype lweight vertices / header data v)
  (setq header
    (list
      '(0 . "LWPOLYLINE")
      '(100 . "AcDbEntity")
      (cons 8 layer)
    )
  )
  (if owner (setq header (append (list (car header) (cons 330 owner)) (cdr header))))
  (if color (setq header (append header (list (cons 62 color)))))
  (if ltype (setq header (append header (list (cons 6 ltype)))))
  (if lweight (setq header (append header (list (cons 370 lweight)))))
  (setq header
    (append
      header
      (list
        '(100 . "AcDbPolyline")
        (cons 90 (length vertices))
        '(70 . 1)
      )
    )
  )
  (setq data header)
  (foreach v vertices
    (setq data
      (append
        data
        (list
          (cons 10 (db:pt2d (car v)))
          (cons 42 (cadr v))
        )
      )
    )
  )
  (entmakex data)
)

(defun db:make-lwpolyline (layer color ltype lweight vertices)
  (db:make-lwpolyline-owned nil layer color ltype lweight vertices)
)

(defun db:make-arc-on-layer (layer center radius start end ccw / a1 a2)
  (setq a1 (db:angle (db:sub start center)))
  (setq a2 (db:angle (db:sub end center)))
  (if ccw
    (entmakex
      (list
        '(0 . "ARC")
        (cons 8 layer)
        (cons 10 (db:pt2 center))
        (cons 40 radius)
        (cons 50 a1)
        (cons 51 a2)
      )
    )
    (entmakex
      (list
        '(0 . "ARC")
        (cons 8 layer)
        (cons 10 (db:pt2 center))
        (cons 40 radius)
        (cons 50 a2)
        (cons 51 a1)
      )
    )
  )
)

(defun db:make-circle (center radius)
  (entmakex
    (list
      '(0 . "CIRCLE")
      (cons 8 *db-layer*)
      (cons 10 (db:pt2 center))
      (cons 40 radius)
    )
  )
)

(defun db:make-patch (type center start end radius ccw label)
  (list
    (cons 'type type)
    (cons 'center center)
    (cons 'start start)
    (cons 'end end)
    (cons 'radius radius)
    (cons 'ccw ccw)
    (cons 'label label)
  )
)

(defun db:make-production-patch (type source-index corner center start end radius bulge angle label)
  (list
    (cons 'type type)
    (cons 'source-index source-index)
    (cons 'corner corner)
    (cons 'center center)
    (cons 'start start)
    (cons 'end end)
    (cons 'radius radius)
    (cons 'bulge bulge)
    (cons 'angle angle)
    (cons 'label label)
  )
)

;;; Confirmed V2 production model: 45-degree dogbone.
;;; Center is one tool radius along the corner bisector. The original corner is
;;; removed, both adjacent edges are shortened to the second circle intersection,
;;; and the remaining circle arc is written as LWPOLYLINE bulge.
(defun db:create-c-patch (p0 p1 p2 radius source-index / v1 v2 dir theta theta-deg cos-half trim center start end bulge)
  (setq v1 (db:norm (db:sub p0 p1)))
  (setq v2 (db:norm (db:sub p2 p1)))
  (if (and v1 v2)
    (progn
      (setq dir (db:norm (db:add v1 v2)))
      (if dir
        (progn
          (setq theta (db:acos (db:dot v1 v2)))
          (setq theta-deg (db:rad->deg theta))
          (setq cos-half (cos (/ theta 2.0)))
          (if (> cos-half *db-eps*)
            (progn
              (if (<= (abs (- theta-deg 90.0)) *db-angle90-tol*)
                (setq trim (* radius (sqrt 2.0)))
                (setq trim (* 2.0 radius cos-half))
              )
              (if (and (<= trim (+ (db:distance p0 p1) *db-eps*))
                       (<= trim (+ (db:distance p2 p1) *db-eps*)))
                (progn
                  (setq center (db:add p1 (db:mul dir radius)))
                  (setq start (db:add p1 (db:mul v1 trim)))
                  (setq end (db:add p1 (db:mul v2 trim)))
                  (setq bulge (db:arc-bulge-near-corner center radius start end p1))
                  (db:make-production-patch "circle-45" source-index p1 center start end radius bulge theta "C 45-Degree")
                )
                nil
              )
            )
            nil
          )
        )
        nil
      )
    )
    nil
  )
)

;;; Phase 0 Mode A: offset-center circle tangent to both corner edges.
(defun db:mode-a-patch (p0 p1 p2 radius / v1 v2 center theta tangent start end)
  (setq v1 (db:norm (db:sub p0 p1)))
  (setq v2 (db:norm (db:sub p2 p1)))
  (setq center (db:dogbone-center p0 p1 p2 radius))
  (if (and v1 v2 center)
    (progn
      (setq theta (db:acos (db:dot v1 v2)))
      (setq tangent
        (/ radius
          (max *db-eps*
            (/ (sin (/ theta 2.0)) (cos (/ theta 2.0)))
          )
        )
      )
      (setq start (db:add p1 (db:mul v1 tangent)))
      (setq end (db:add p1 (db:mul v2 tangent)))
      (db:make-patch "A" center start end radius nil "A Offset-Center")
    )
    nil
  )
)

;;; Phase 0 Mode B: circle center stays exactly on the original corner.
(defun db:mode-b-patch (p0 p1 p2 radius / v1 v2 start end)
  (setq v1 (db:norm (db:sub p0 p1)))
  (setq v2 (db:norm (db:sub p2 p1)))
  (if (and v1 v2)
    (progn
      (setq start (db:add p1 (db:mul v1 radius)))
      (setq end (db:add p1 (db:mul v2 radius)))
      (db:make-patch "B" p1 start end radius nil "B Corner-Centered")
    )
    nil
  )
)

;;; Phase 0 Mode C: 45-degree dogbone candidate.
;;; The center moves one tool radius along the corner bisector. This keeps the
;;; test simple and makes the 45-degree release direction visible for review.
(defun db:mode-c-patch (p0 p1 p2 radius / v1 v2 dir center start end)
  (setq v1 (db:norm (db:sub p0 p1)))
  (setq v2 (db:norm (db:sub p2 p1)))
  (if (and v1 v2)
    (progn
      (setq dir (db:norm (db:add v1 v2)))
      (if dir
        (progn
          (setq center (db:add p1 (db:mul dir radius)))
          (setq start p1)
          (setq end (db:add center (db:mul dir radius)))
          (db:make-patch "C" center start end radius nil "C 45-Degree")
        )
        nil
      )
    )
    nil
  )
)

(defun db:draw-test-patch (layer patch / center start end radius label mid textpt)
  (if patch
    (progn
      (setq center (cdr (assoc 'center patch)))
      (setq start (cdr (assoc 'start patch)))
      (setq end (cdr (assoc 'end patch)))
      (setq radius (cdr (assoc 'radius patch)))
      (setq label (cdr (assoc 'label patch)))
      (setq mid (db:mul (db:add start end) 0.5))
      (setq textpt (db:add center (list (* radius 0.35) (* radius 0.35) 0.0)))
      (db:make-circle-on-layer layer center radius)
      (db:make-arc-on-layer layer center radius start end nil)
      (db:make-line-on-layer layer center start)
      (db:make-line-on-layer layer center end)
      (db:make-point-on-layer layer center)
      (db:make-point-on-layer layer start)
      (db:make-point-on-layer layer end)
      (db:make-text-on-layer layer textpt (* radius 0.35) label)
    )
  )
)

(defun db:make-point (pt)
  (entmakex
    (list
      '(0 . "POINT")
      (cons 8 *db-layer*)
      (cons 10 (db:pt2 pt))
    )
  )
)

;;; Calculate signed polygon area.
;;; Positive area means the vertex order is counter-clockwise in WCS XY.
(defun db:poly-area (pts / sum p q rest)
  (setq sum 0.0)
  (setq rest pts)
  (while rest
    (setq p (car rest))
    (setq q (if (cdr rest) (cadr rest) (car pts)))
    (setq sum (+ sum (- (* (db:x p) (db:y q)) (* (db:y p) (db:x q)))))
    (setq rest (cdr rest))
  )
  (/ sum 2.0)
)

;;; Ray-casting point-in-polygon test for straight-segment closed polylines.
(defun db:point-in-poly (pt pts / inside i j pi pj xi yi xj yj px py n hit)
  (setq inside nil)
  (setq n (length pts))
  (setq i 0)
  (setq j (- n 1))
  (setq px (db:x pt))
  (setq py (db:y pt))
  (while (< i n)
    (setq pi (nth i pts))
    (setq pj (nth j pts))
    (setq xi (db:x pi))
    (setq yi (db:y pi))
    (setq xj (db:x pj))
    (setq yj (db:y pj))
    (setq hit
      (and
        (/= (> yi py) (> yj py))
        (< px (+ xi (/ (* (- xj xi) (- py yi)) (- yj yi))))
      )
    )
    (if hit (setq inside (not inside)))
    (setq j i)
    (setq i (1+ i))
  )
  inside
)

;;; Parse an LWPOLYLINE into:
;;;   (closedFlag ((point bulgeAfter) ...))
;;; Bulge belongs to the segment starting at that point. Any non-zero bulge is
;;; skipped by DBAUTO because this release handles only straight source edges.
(defun db:lwpoly-data (ename / ed closed verts curpt curbulge d)
  (setq ed (entget ename))
  (setq closed (= 1 (logand 1 (cdr (assoc 70 ed)))))
  (setq verts '())
  (setq curpt nil)
  (setq curbulge 0.0)
  (foreach d ed
    (cond
      ((= (car d) 10)
        (if curpt
          (setq verts (cons (list curpt curbulge) verts))
        )
        (setq curpt (db:pt2 (cdr d)))
        (setq curbulge 0.0)
      )
      ((= (car d) 42)
        (setq curbulge (float (cdr d)))
      )
    )
  )
  (if curpt
    (setq verts (cons (list curpt curbulge) verts))
  )
  (list closed (reverse verts))
)

(defun db:has-bulge (verts / found v)
  (setq found nil)
  (foreach v verts
    (if (> (abs (cadr v)) *db-eps*)
      (setq found T)
    )
  )
  found
)

(defun db:vertex-points (verts / pts v)
  (setq pts '())
  (foreach v verts
    (setq pts (cons (car v) pts))
  )
  (reverse pts)
)

;;; Decide whether a selected polyline is a hole by containment.
;;; If a boundary is inside an odd number of other selected boundaries, it is
;;; treated as a hole. This avoids depending only on drawing direction.
(defun db:is-hole (idx items / item pt count j other)
  (setq item (nth idx items))
  (setq pt (car (cadr item)))
  (setq count 0)
  (setq j 0)
  (while (< j (length items))
    (if (/= j idx)
      (progn
        (setq other (nth j items))
        (if (db:point-in-poly pt (cadr other))
          (setq count (1+ count))
        )
      )
    )
    (setq j (1+ j))
  )
  (= 1 (rem count 2))
)

;;; Return T when the vertex should receive a dogbone.
;;; For outer boundaries, a dogbone is needed at concave vertices.
;;; For hole boundaries, material lies outside the polyline, so convex vertices
;;; are the CNC internal corners that need dogbones.
(defun db:needs-dogbone (p0 p1 p2 area is-hole / vin vout turn area-sign turn-sign)
  (setq vin (db:sub p1 p0))
  (setq vout (db:sub p2 p1))
  (setq turn (db:crossz vin vout))
  (if (< (abs turn) *db-eps*)
    nil
    (progn
      (setq area-sign (if (> area 0.0) 1.0 -1.0))
      (setq turn-sign (if (> turn 0.0) 1.0 -1.0))
      (if is-hole
        (= area-sign turn-sign)  ; convex relative to the hole void
        (/= area-sign turn-sign) ; concave relative to the outer outline
      )
    )
  )
)

;;; Dogbone center from the specification:
;;;   v1 = normalize(P0 - P1)
;;;   v2 = normalize(P2 - P1)
;;;   center direction = normalize(v1 + v2)
;;;   distance = R / sin(theta / 2)
(defun db:dogbone-center (p0 p1 p2 radius / v1 v2 dir dot theta s dist)
  (setq v1 (db:norm (db:sub p0 p1)))
  (setq v2 (db:norm (db:sub p2 p1)))
  (if (and v1 v2)
    (progn
      (setq dir (db:norm (db:add v1 v2)))
      (setq dot (db:dot v1 v2))
      (setq theta (db:acos dot))
      (setq s (sin (/ theta 2.0)))
      (if (and dir (> s *db-eps*))
        (progn
          (setq dist (/ radius s))
          (db:add p1 (db:mul dir dist))
        )
        nil
      )
    )
    nil
  )
)

(defun db:yes-no-prompt (msg default / ans)
  (initget "Yes No")
  (setq ans
    (getkword
      (strcat "\n" msg " [Yes/No] <" (db:bool-text default) ">: ")
    )
  )
  (cond
    ((= ans "Yes") T)
    ((= ans "No") nil)
    (T default)
  )
)

(defun db:start-undo ()
  (command "_.UNDO" "_Begin")
)

(defun db:end-undo ()
  (command "_.UNDO" "_End")
)

(defun c:DBSET (/ d)
  (db:ensure-defaults)
  (prompt "\nDogbone settings.")
  (setq d (getreal (strcat "\nTool diameter <" (rtos *db-tool-dia* 2 3) ">: ")))
  (if (and d (> d 0.0))
    (setq *db-tool-dia* d)
  )
  (setq *db-process-holes*
    (db:yes-no-prompt "Process contained hole outlines" *db-process-holes*)
  )
  (setq *db-layer* "DOGBONE")
  (setq *db-dogbone-type* "C")
  (setq *db-duplicate-tol* 0.01)
  (setq *db-angle90-tol* 0.1)
  (setq *db-keep-original* nil)
  (setq *db-debug-mode* nil)
  (setq *db-preview* nil)
  (prompt
    (strcat
      "\nDBSET complete. Tool diameter="
      (rtos *db-tool-dia* 2 3)
      ", radius="
      (rtos (db:radius) 2 3)
      ", holes="
      (db:bool-text *db-process-holes*)
      ". Production defaults: type=C, delete old polyline=Yes, debug=No, preview=No."
    )
  )
  (princ)
)

(defun c:DB1 (/ olderr p1 p0 p2 r pa pb pc)
  (db:ensure-defaults)
  (setq olderr *error*)
  (defun *error* (msg)
    (db:end-undo)
    (setq *error* olderr)
    (if (and msg (/= msg "Function cancelled"))
      (prompt (strcat "\nError: " msg))
    )
    (princ)
  )
  (db:start-undo)
  (db:ensure-named-layer "DB_TEST_A" 1)
  (db:ensure-named-layer "DB_TEST_B" 2)
  (db:ensure-named-layer "DB_TEST_C" 3)
  (setq r (db:radius))
  (setq p1 (getpoint "\nPick corner point: "))
  (if p1
    (progn
      (setq p0 (getpoint p1 "\nPick a point in the previous-edge direction: "))
      (setq p2 (getpoint p1 "\nPick a point in the next-edge direction: "))
      (if (and p0 p2)
        (progn
          (setq p0 (db:pt2 p0))
          (setq p1 (db:pt2 p1))
          (setq p2 (db:pt2 p2))
          (setq pa (db:mode-a-patch p0 p1 p2 r))
          (setq pb (db:mode-b-patch p0 p1 p2 r))
          (setq pc (db:mode-c-patch p0 p1 p2 r))
          (if (and pa pb pc)
            (progn
              (db:draw-test-patch "DB_TEST_A" pa)
              (db:draw-test-patch "DB_TEST_B" pb)
              (db:draw-test-patch "DB_TEST_C" pc)
              (prompt "\nDB1 created A/B/C dogbone test geometry on DB_TEST_A, DB_TEST_B, DB_TEST_C.")
            )
            (prompt "\nDB1 skipped: points are collinear or too close together.")
          )
        )
      )
    )
  )
  (db:end-undo)
  (setq *error* olderr)
  (princ)
)

(defun db:collect-entities (entities / en data ed verts pts area items skipped-open skipped-bulge layer color ltype lweight)
  (setq items '())
  (setq skipped-open 0)
  (setq skipped-bulge 0)
  (foreach en entities
    (setq ed (entget en))
    (setq data (db:lwpoly-data en))
    (setq verts (cadr data))
    (cond
      ((not (car data))
        (setq skipped-open (1+ skipped-open))
      )
      ((< (length verts) 3)
        (setq skipped-open (1+ skipped-open))
      )
      ((db:has-bulge verts)
        (setq skipped-bulge (1+ skipped-bulge))
      )
      (T
        (setq pts (db:vertex-points verts))
        (setq area (db:poly-area pts))
        (if (> (abs area) *db-eps*)
          (progn
            (setq layer (cdr (assoc 8 ed)))
            (setq color (cdr (assoc 62 ed)))
            (setq ltype (cdr (assoc 6 ed)))
            (setq lweight (cdr (assoc 370 ed)))
            (setq items (cons (list en pts area nil layer color ltype lweight) items))
          )
          (setq skipped-open (1+ skipped-open))
        )
      )
    )
  )
  (list (reverse items) skipped-open skipped-bulge)
)

(defun db:collect-selection (ss / i entities)
  (setq i 0)
  (setq entities '())
  (while (< i (sslength ss))
    (setq entities (cons (ssname ss i) entities))
    (setq i (1+ i))
  )
  (db:collect-entities (reverse entities))
)

(defun db:near-one-p (value)
  (<= (abs (- (float value) 1.0)) *db-eps*)
)

(defun db:unit-scale-insert-p (ed / sx sy sz)
  (setq sx (db:assoc-value 41 ed 1.0))
  (setq sy (db:assoc-value 42 ed 1.0))
  (setq sz (db:assoc-value 43 ed 1.0))
  (and (db:near-one-p sx) (db:near-one-p sy) (db:near-one-p sz))
)

(defun db:string-member-p (value values / found item)
  (setq found nil)
  (foreach item values
    (if (= value item) (setq found T))
  )
  found
)

(defun db:editable-block-definition-p (blockname / bdef flags)
  (setq bdef (tblsearch "BLOCK" blockname))
  (if (or (not bdef) (= (substr blockname 1 1) "*"))
    nil
    (progn
      (setq flags (db:assoc-value 70 bdef 0))
      (= 0 (logand flags (+ 4 8 16)))
    )
  )
)

;;; Collect only direct LWPOLYLINE children. Nested INSERT definitions are not
;;; modified because they may be shared by unrelated parent blocks.
(defun db:collect-block-polylines (blockname / bdef en ed etype result)
  (setq bdef (tblsearch "BLOCK" blockname))
  (setq result '())
  (if bdef
    (progn
      (setq en (cdr (assoc -2 bdef)))
      (while en
        (setq ed (entget en))
        (setq etype (cdr (assoc 0 ed)))
        (cond
          ((= etype "ENDBLK") (setq en nil))
          ((= etype "LWPOLYLINE")
            (setq result (cons en result))
            (setq en (entnext en))
          )
          (T (setq en (entnext en)))
        )
      )
    )
  )
  (reverse result)
)

;;; Return mixed DBAUTO selection as independent containment groups:
;;;   ((groups . ((direct nil items) (block name items) ...)) ...counters...)
(defun db:collect-dbauto-groups (ss / i en ed etype direct-entities seen-blocks groups
                                    blockname block-entities collected skipped-blocks
                                    skipped-open skipped-bulge direct-count block-count)
  (setq i 0)
  (setq direct-entities '())
  (setq seen-blocks '())
  (setq groups '())
  (setq skipped-blocks 0)
  (setq skipped-open 0)
  (setq skipped-bulge 0)
  (setq block-count 0)
  (while (< i (sslength ss))
    (setq en (ssname ss i))
    (setq ed (entget en))
    (setq etype (cdr (assoc 0 ed)))
    (cond
      ((= etype "LWPOLYLINE")
        (setq direct-entities (cons en direct-entities))
      )
      ((= etype "INSERT")
        (setq blockname (cdr (assoc 2 ed)))
        (cond
          ((not (db:unit-scale-insert-p ed))
            (setq skipped-blocks (1+ skipped-blocks))
          )
          ((or (not blockname)
               (not (db:editable-block-definition-p blockname)))
            (setq skipped-blocks (1+ skipped-blocks))
          )
          ((not (db:string-member-p blockname seen-blocks))
            (setq seen-blocks (cons blockname seen-blocks))
            (setq block-entities (db:collect-block-polylines blockname))
            (if block-entities
              (progn
                (setq collected (db:collect-entities block-entities))
                (setq groups (append groups (list (list 'block blockname (car collected)))))
                (setq block-count (1+ block-count))
                (setq skipped-open (+ skipped-open (cadr collected)))
                (setq skipped-bulge (+ skipped-bulge (caddr collected)))
              )
              (setq skipped-blocks (1+ skipped-blocks))
            )
          )
        )
      )
    )
    (setq i (1+ i))
  )
  (setq direct-entities (reverse direct-entities))
  (setq direct-count 0)
  (if direct-entities
    (progn
      (setq collected (db:collect-entities direct-entities))
      (setq direct-count (length (car collected)))
      (setq groups (cons (list 'direct nil (car collected)) groups))
      (setq skipped-open (+ skipped-open (cadr collected)))
      (setq skipped-bulge (+ skipped-bulge (caddr collected)))
    )
  )
  (list
    (cons 'groups groups)
    (cons 'direct-count direct-count)
    (cons 'block-count block-count)
    (cons 'skipped-blocks skipped-blocks)
    (cons 'skipped-open skipped-open)
    (cons 'skipped-bulge skipped-bulge)
  )
)

(defun db:collect-edit-selection (ss / i en ed data verts pts area items skipped-open layer color ltype lweight)
  (setq i 0)
  (setq items '())
  (setq skipped-open 0)
  (while (< i (sslength ss))
    (setq en (ssname ss i))
    (setq ed (entget en))
    (setq data (db:lwpoly-data en))
    (setq verts (cadr data))
    (if (and (car data) (>= (length verts) 3))
      (progn
        (setq pts (db:vertex-points verts))
        (setq area (db:poly-area pts))
        (if (> (abs area) *db-eps*)
          (progn
            (setq layer (cdr (assoc 8 ed)))
            (setq color (cdr (assoc 62 ed)))
            (setq ltype (cdr (assoc 6 ed)))
            (setq lweight (cdr (assoc 370 ed)))
            (setq items (cons (list en pts area nil layer color ltype lweight verts) items))
          )
          (setq skipped-open (1+ skipped-open))
        )
      )
      (setq skipped-open (1+ skipped-open))
    )
    (setq i (1+ i))
  )
  (list (reverse items) skipped-open)
)

(defun db:tag-holes (items / tagged i item is-hole)
  (setq tagged '())
  (setq i 0)
  (while (< i (length items))
    (setq item (nth i items))
    (setq is-hole (db:is-hole i items))
    (setq tagged
      (cons
        (append (list (car item) (cadr item) (caddr item) is-hole) (cddddr item))
        tagged
      )
    )
    (setq i (1+ i))
  )
  (reverse tagged)
)

(defun db:process-poly (item / pts area is-hole n i p0 p1 p2 center r made corners)
  (setq pts (cadr item))
  (setq area (caddr item))
  (setq is-hole (cadddr item))
  (setq n (length pts))
  (setq i 0)
  (setq made 0)
  (setq corners 0)
  (setq r (db:radius))
  (if (and is-hole (not *db-process-holes*))
    (list 0 0)
    (progn
      (while (< i n)
        (setq p0 (nth (rem (+ i n -1) n) pts))
        (setq p1 (nth i pts))
        (setq p2 (nth (rem (1+ i) n) pts))
        (if (db:needs-dogbone p0 p1 p2 area is-hole)
          (progn
            (setq corners (1+ corners))
            (setq center (db:dogbone-center p0 p1 p2 r))
            (if center
              (progn
                (db:make-circle center r)
                (if *db-preview* (db:make-point p1))
                (setq made (1+ made))
              )
            )
          )
        )
        (setq i (1+ i))
      )
      (list corners made)
    )
  )
)

(defun db:find-patch (idx patches / found p)
  (setq found nil)
  (foreach p patches
    (if (= idx (cdr (assoc 'source-index p)))
      (setq found p)
    )
  )
  found
)

(defun db:item-verts (item)
  (nth 8 item)
)

(defun db:vertex-bulge (verts idx)
  (cadr (nth idx verts))
)

(defun db:sharp-corner-p (verts idx / n prev-bulge this-bulge)
  (setq n (length verts))
  (setq prev-bulge (db:vertex-bulge verts (rem (+ idx n -1) n)))
  (setq this-bulge (db:vertex-bulge verts idx))
  (and
    (<= (abs prev-bulge) *db-eps*)
    (<= (abs this-bulge) *db-eps*)
  )
)

(defun db:add-corner-match-p (pt rect)
  (db:point-in-rect pt rect)
)

(defun db:build-add-patches (item rect existing / pts area is-hole verts n i p0 p1 p2 patch patches corners dupes)
  (setq pts (cadr item))
  (setq area (caddr item))
  (setq is-hole (cadddr item))
  (setq verts (db:item-verts item))
  (setq n (length pts))
  (setq i 0)
  (setq patches '())
  (setq corners 0)
  (setq dupes 0)
  (if (and is-hole (not *db-process-holes*))
    (list '() 0 0)
    (progn
      (while (< i n)
        (setq p0 (nth (rem (+ i n -1) n) pts))
        (setq p1 (nth i pts))
        (setq p2 (nth (rem (1+ i) n) pts))
        (if (and
              (db:sharp-corner-p verts i)
              (db:needs-dogbone p0 p1 p2 area is-hole)
              (db:add-corner-match-p p1 rect)
            )
          (progn
            (setq corners (1+ corners))
            (setq patch (db:create-patch p0 p1 p2 i))
            (if patch
              (if (db:duplicate-patch-p patch (append existing patches) *db-duplicate-tol*)
                (setq dupes (1+ dupes))
                (setq patches (cons patch patches))
              )
            )
          )
        )
        (setq i (1+ i))
      )
      (list (reverse patches) corners dupes)
    )
  )
)

(defun db:duplicate-patch-p (patch patches tol / dup p)
  (setq dup nil)
  (foreach p patches
    (if (and
          (<= (db:distance (cdr (assoc 'corner patch)) (cdr (assoc 'corner p))) tol)
          (<= (abs (- (cdr (assoc 'radius patch)) (cdr (assoc 'radius p)))) tol)
        )
      (setq dup T)
    )
  )
  dup
)

(defun db:create-patch (p0 p1 p2 index / r)
  (setq r (db:radius))
  (cond
    ((= *db-dogbone-type* "C")
      (db:create-c-patch p0 p1 p2 r index)
    )
    (T
      (db:create-c-patch p0 p1 p2 r index)
    )
  )
)

(defun db:build-patches (item existing / pts area is-hole n i p0 p1 p2 patch patches corners dupes)
  (setq pts (cadr item))
  (setq area (caddr item))
  (setq is-hole (cadddr item))
  (setq n (length pts))
  (setq i 0)
  (setq patches '())
  (setq corners 0)
  (setq dupes 0)
  (if (and is-hole (not *db-process-holes*))
    (list '() 0 0)
    (progn
      (while (< i n)
        (setq p0 (nth (rem (+ i n -1) n) pts))
        (setq p1 (nth i pts))
        (setq p2 (nth (rem (1+ i) n) pts))
        (if (db:needs-dogbone p0 p1 p2 area is-hole)
          (progn
            (setq corners (1+ corners))
            (setq patch (db:create-patch p0 p1 p2 i))
            (if patch
              (if (db:duplicate-patch-p patch (append existing patches) *db-duplicate-tol*)
                (setq dupes (1+ dupes))
                (setq patches (cons patch patches))
              )
            )
          )
        )
        (setq i (1+ i))
      )
      (list (reverse patches) corners dupes)
    )
  )
)

(defun db:rebuild-polyline (item patches / pts layer color ltype lweight owner n i patch vertices)
  (setq pts (cadr item))
  (setq layer (nth 4 item))
  (if (not layer) (setq layer "0"))
  (setq color (nth 5 item))
  (setq ltype (nth 6 item))
  (setq lweight (nth 7 item))
  (setq owner (cdr (assoc 330 (entget (car item)))))
  (setq n (length pts))
  (setq i 0)
  (setq vertices '())
  (while (< i n)
    (setq patch (db:find-patch i patches))
    (if patch
      (progn
        (setq vertices
          (append
            vertices
            (list
              (list (cdr (assoc 'start patch)) (cdr (assoc 'bulge patch)))
              (list (cdr (assoc 'end patch)) 0.0)
            )
          )
        )
      )
      (setq vertices (append vertices (list (list (nth i pts) 0.0))))
    )
    (setq i (1+ i))
  )
  (if (>= (length vertices) 3)
    (db:make-lwpolyline-owned owner layer color ltype lweight vertices)
    nil
  )
)

(defun db:rebuild-edit-polyline-add (item patches / verts layer color ltype lweight n i patch vertices)
  (setq verts (db:item-verts item))
  (setq layer (nth 4 item))
  (if (not layer) (setq layer "0"))
  (setq color (nth 5 item))
  (setq ltype (nth 6 item))
  (setq lweight (nth 7 item))
  (setq n (length verts))
  (setq i 0)
  (setq vertices '())
  (while (< i n)
    (setq patch (db:find-patch i patches))
    (if patch
      (setq vertices
        (append
          vertices
          (list
            (list (cdr (assoc 'start patch)) (cdr (assoc 'bulge patch)))
            (list (cdr (assoc 'end patch)) 0.0)
          )
        )
      )
      (setq vertices
        (append vertices (list (list (car (nth i verts)) (cadr (nth i verts)))))
      )
    )
    (setq i (1+ i))
  )
  (if (>= (length vertices) 3)
    (db:make-lwpolyline layer color ltype lweight vertices)
    nil
  )
)

(defun db:dogbone-bulge-p (bulge)
  (<= (abs (- (abs bulge) 1.0)) *db-restore-bulge-tol*)
)

(defun db:restore-candidate (verts idx / n start end bulge chord len mid left sign radius corner)
  (setq n (length verts))
  (setq start (car (nth idx verts)))
  (setq end (car (nth (rem (1+ idx) n) verts)))
  (setq bulge (cadr (nth idx verts)))
  (if (and (db:dogbone-bulge-p bulge) (> (db:distance start end) *db-eps*))
    (progn
      (setq chord (db:sub end start))
      (setq len (db:len chord))
      (setq mid (db:mul (db:add start end) 0.5))
      (setq left (list (- (/ (db:y chord) len)) (/ (db:x chord) len) 0.0))
      (setq sign (if (> bulge 0.0) 1.0 -1.0))
      (setq radius (/ len 2.0))
      (setq corner (db:add mid (db:mul left (* -1.0 sign radius))))
      (list
        (cons 'source-index idx)
        (cons 'start start)
        (cons 'end end)
        (cons 'center mid)
        (cons 'corner corner)
        (cons 'midpoint corner)
        (cons 'radius radius)
        (cons 'bulge bulge)
      )
    )
    nil
  )
)

(defun db:restore-candidate-match-p (cand rect)
  (or
    (db:point-in-rect (cdr (assoc 'corner cand)) rect)
    (db:point-in-rect (cdr (assoc 'center cand)) rect)
    (db:point-in-rect (cdr (assoc 'midpoint cand)) rect)
  )
)

(defun db:find-restore-candidate (idx candidates / found c)
  (setq found nil)
  (foreach c candidates
    (if (= idx (cdr (assoc 'source-index c)))
      (setq found c)
    )
  )
  found
)

(defun db:build-restore-candidates (item rect / verts n i cand selected matched)
  (setq verts (db:item-verts item))
  (setq n (length verts))
  (setq i 0)
  (setq selected '())
  (setq matched 0)
  (while (< i n)
    (setq cand (db:restore-candidate verts i))
    (if (and cand (db:restore-candidate-match-p cand rect))
      (progn
        (setq selected (cons cand selected))
        (setq matched (1+ matched))
      )
    )
    (setq i (1+ i))
  )
  (list (reverse selected) matched)
)

(defun db:build-all-restore-candidates (item / verts n i cand selected matched)
  (setq verts (db:item-verts item))
  (setq n (length verts))
  (setq i 0)
  (setq selected '())
  (setq matched 0)
  (while (< i n)
    (setq cand (db:restore-candidate verts i))
    (if cand
      (progn
        (setq selected (cons cand selected))
        (setq matched (1+ matched))
      )
    )
    (setq i (1+ i))
  )
  (list (reverse selected) matched)
)

(defun db:rebuild-restore (item candidates / verts layer color ltype lweight n i cand vertices skip skip0)
  (setq verts (db:item-verts item))
  (setq layer (nth 4 item))
  (if (not layer) (setq layer "0"))
  (setq color (nth 5 item))
  (setq ltype (nth 6 item))
  (setq lweight (nth 7 item))
  (setq n (length verts))
  (setq i 0)
  (setq vertices '())
  (setq skip '())
  (setq skip0 (if (db:find-restore-candidate (- n 1) candidates) T nil))
  (while (< i n)
    (cond
      ((and (= i 0) skip0)
        nil
      )
      ((db:list-has-int i skip)
        nil
      )
      ((setq cand (db:find-restore-candidate i candidates))
        (setq vertices
          (append vertices (list (list (cdr (assoc 'corner cand)) 0.0)))
        )
        (if (= i (- n 1))
          (setq skip (cons 0 skip))
          (setq skip (cons (1+ i) skip))
        )
      )
      (T
        (setq vertices
          (append vertices (list (list (car (nth i verts)) (cadr (nth i verts)))))
        )
      )
    )
    (setq i (1+ i))
  )
  (if (>= (length vertices) 3)
    (db:make-lwpolyline layer color ltype lweight vertices)
    nil
  )
)

(defun db:ensure-debug-layers ()
  (db:ensure-named-layer "DBDEBUG_CORNER" 1)
  (db:ensure-named-layer "DBDEBUG_CENTER" 5)
  (db:ensure-named-layer "DBDEBUG_TANGENT" 2)
  (db:ensure-named-layer "DBDEBUG_DIRECTION" 3)
  (db:ensure-named-layer "DBDEBUG_TEXT" 7)
  (db:ensure-named-layer "DBDEBUG_CIRCLE" 1)
)

(defun db:draw-debug-patch (patch / corner center start end radius angle label textpt)
  (setq corner (cdr (assoc 'corner patch)))
  (setq center (cdr (assoc 'center patch)))
  (setq start (cdr (assoc 'start patch)))
  (setq end (cdr (assoc 'end patch)))
  (setq radius (cdr (assoc 'radius patch)))
  (setq angle (cdr (assoc 'angle patch)))
  (setq label (strcat (rtos (db:rad->deg angle) 2 2) " deg"))
  (setq textpt (db:add center (list (* radius 0.5) (* radius 0.5) 0.0)))
  (db:make-point-on-layer "DBDEBUG_CORNER" corner)
  (db:make-point-on-layer "DBDEBUG_CENTER" center)
  (db:make-point-on-layer "DBDEBUG_TANGENT" start)
  (db:make-point-on-layer "DBDEBUG_TANGENT" end)
  (db:make-line-on-layer "DBDEBUG_DIRECTION" corner center)
  (db:make-line-on-layer "DBDEBUG_DIRECTION" corner start)
  (db:make-line-on-layer "DBDEBUG_DIRECTION" corner end)
  (db:make-circle-on-layer "DBDEBUG_CIRCLE" center radius)
  (db:make-text-on-layer "DBDEBUG_TEXT" textpt (* radius 0.35) label)
)

(defun db:get-edit-window (/ p1 p2)
  (setq p1 (getpoint "\nFirst window corner around target corner(s): "))
  (if p1
    (progn
      (setq p2 (getcorner p1 "\nOpposite window corner: "))
      (if p2
        (db:rect-from-points (db:pt2 p1) (db:pt2 p2))
        nil
      )
    )
    nil
  )
)

(defun c:DBADD (/ olderr ss rect collected items skipped-open tagged
                  item result patches all-patches poly-count hole-count corner-count
                  dogbone-count duplicate-count rebuilt-count newent)
  (db:ensure-defaults)
  (setq olderr *error*)
  (defun *error* (msg)
    (db:end-undo)
    (setq *error* olderr)
    (if (and msg (/= msg "Function cancelled"))
      (prompt (strcat "\nError: " msg))
    )
    (princ)
  )
  (prompt "\nSelect closed LWPOLYLINE outlines to add local dogbones.")
  (setq ss (ssget '((0 . "LWPOLYLINE"))))
  (if ss
    (progn
      (setq rect (db:get-edit-window))
      (if rect
        (progn
          (db:start-undo)
          (setq collected (db:collect-edit-selection ss))
          (setq items (car collected))
          (setq skipped-open (cadr collected))
          (setq tagged (db:tag-holes items))
          (setq poly-count (length tagged))
          (setq hole-count 0)
          (setq corner-count 0)
          (setq dogbone-count 0)
          (setq duplicate-count 0)
          (setq rebuilt-count 0)
          (setq all-patches '())
          (foreach item tagged
            (if (cadddr item) (setq hole-count (1+ hole-count)))
            (setq result (db:build-add-patches item rect all-patches))
            (setq patches (car result))
            (setq all-patches (append all-patches patches))
            (setq corner-count (+ corner-count (cadr result)))
            (setq dogbone-count (+ dogbone-count (length patches)))
            (setq duplicate-count (+ duplicate-count (caddr result)))
            (if patches
              (progn
                (setq newent (db:rebuild-edit-polyline-add item patches))
                (if newent
                  (progn
                    (setq rebuilt-count (1+ rebuilt-count))
                    (entdel (car item))
                  )
                )
              )
            )
          )
          (db:end-undo)
          (prompt
            (strcat
              "\nDBADD complete. Selected="
              (itoa (sslength ss))
              ", valid="
              (itoa poly-count)
              ", skipped="
              (itoa skipped-open)
              ", holes="
              (itoa hole-count)
              ", matched corners="
              (itoa corner-count)
              ", dogbones added="
              (itoa dogbone-count)
              ", duplicates skipped="
              (itoa duplicate-count)
              ", rebuilt polylines="
              (itoa rebuilt-count)
              "."
            )
          )
        )
        (prompt "\nDBADD cancelled.")
      )
    )
    (prompt "\nNothing selected.")
  )
  (setq *error* olderr)
  (princ)
)

(defun c:DBRESTORE (/ olderr ss rect collected items skipped-open tagged
                      item result candidates poly-count restored-count matched-count rebuilt-count newent)
  (db:ensure-defaults)
  (setq olderr *error*)
  (defun *error* (msg)
    (db:end-undo)
    (setq *error* olderr)
    (if (and msg (/= msg "Function cancelled"))
      (prompt (strcat "\nError: " msg))
    )
    (princ)
  )
  (prompt "\nSelect closed LWPOLYLINE outlines to restore dogbone corners.")
  (setq ss (ssget '((0 . "LWPOLYLINE"))))
  (if ss
    (progn
      (setq rect (db:get-edit-window))
      (if rect
        (progn
          (db:start-undo)
          (setq collected (db:collect-edit-selection ss))
          (setq items (car collected))
          (setq skipped-open (cadr collected))
          (setq tagged (db:tag-holes items))
          (setq poly-count (length tagged))
          (setq matched-count 0)
          (setq restored-count 0)
          (setq rebuilt-count 0)
          (foreach item tagged
            (setq result (db:build-restore-candidates item rect))
            (setq candidates (car result))
            (setq matched-count (+ matched-count (cadr result)))
            (setq restored-count (+ restored-count (length candidates)))
            (if candidates
              (progn
                (setq newent (db:rebuild-restore item candidates))
                (if newent
                  (progn
                    (setq rebuilt-count (1+ rebuilt-count))
                    (entdel (car item))
                  )
                )
              )
            )
          )
          (db:end-undo)
          (prompt
            (strcat
              "\nDBRESTORE complete. Selected="
              (itoa (sslength ss))
              ", valid="
              (itoa poly-count)
              ", skipped="
              (itoa skipped-open)
              ", matched dogbones="
              (itoa matched-count)
              ", restored dogbones="
              (itoa restored-count)
              ", rebuilt polylines="
              (itoa rebuilt-count)
              "."
            )
          )
        )
        (prompt "\nDBRESTORE cancelled.")
      )
    )
    (prompt "\nNothing selected.")
  )
  (setq *error* olderr)
  (princ)
)

(defun c:DBRESTOREALL (/ olderr ss collected items skipped-open tagged
                         item result candidates poly-count restored-count matched-count rebuilt-count newent)
  (db:ensure-defaults)
  (setq olderr *error*)
  (defun *error* (msg)
    (db:end-undo)
    (setq *error* olderr)
    (if (and msg (/= msg "Function cancelled"))
      (prompt (strcat "\nError: " msg))
    )
    (princ)
  )
  (prompt "\nSelect closed LWPOLYLINE outlines to restore all dogbone corners.")
  (setq ss (ssget '((0 . "LWPOLYLINE"))))
  (if ss
    (progn
      (db:start-undo)
      (setq collected (db:collect-edit-selection ss))
      (setq items (car collected))
      (setq skipped-open (cadr collected))
      (setq tagged (db:tag-holes items))
      (setq poly-count (length tagged))
      (setq matched-count 0)
      (setq restored-count 0)
      (setq rebuilt-count 0)
      (foreach item tagged
        (setq result (db:build-all-restore-candidates item))
        (setq candidates (car result))
        (setq matched-count (+ matched-count (cadr result)))
        (setq restored-count (+ restored-count (length candidates)))
        (if candidates
          (progn
            (setq newent (db:rebuild-restore item candidates))
            (if newent
              (progn
                (setq rebuilt-count (1+ rebuilt-count))
                (entdel (car item))
              )
            )
          )
        )
      )
      (db:end-undo)
      (prompt
        (strcat
          "\nDBRESTOREALL complete. Selected="
          (itoa (sslength ss))
          ", valid="
          (itoa poly-count)
          ", skipped="
          (itoa skipped-open)
          ", matched dogbones="
          (itoa matched-count)
          ", restored dogbones="
          (itoa restored-count)
          ", rebuilt polylines="
          (itoa rebuilt-count)
          "."
        )
      )
    )
    (prompt "\nNothing selected.")
  )
  (setq *error* olderr)
  (princ)
)

(defun c:DBDEBUG (/ olderr ss collected items skipped-open skipped-bulge tagged
                    item result patch patches all-patches poly-count hole-count corner-count dogbone-count duplicate-count)
  (db:ensure-defaults)
  (setq olderr *error*)
  (defun *error* (msg)
    (db:end-undo)
    (setq *error* olderr)
    (if (and msg (/= msg "Function cancelled"))
      (prompt (strcat "\nError: " msg))
    )
    (princ)
  )
  (prompt "\nSelect closed LWPOLYLINE outlines for dogbone debug.")
  (setq ss (ssget '((0 . "LWPOLYLINE"))))
  (if ss
    (progn
      (db:start-undo)
      (db:ensure-debug-layers)
      (setq collected (db:collect-selection ss))
      (setq items (car collected))
      (setq skipped-open (cadr collected))
      (setq skipped-bulge (caddr collected))
      (setq tagged (db:tag-holes items))
      (setq poly-count (length tagged))
      (setq hole-count 0)
      (setq corner-count 0)
      (setq dogbone-count 0)
      (setq duplicate-count 0)
      (setq all-patches '())
      (foreach item tagged
        (if (cadddr item) (setq hole-count (1+ hole-count)))
        (setq result (db:build-patches item all-patches))
        (setq patches (car result))
        (setq all-patches (append all-patches patches))
        (setq corner-count (+ corner-count (cadr result)))
        (setq dogbone-count (+ dogbone-count (length patches)))
        (setq duplicate-count (+ duplicate-count (caddr result)))
        (foreach patch patches
          (db:draw-debug-patch patch)
        )
      )
      (db:end-undo)
      (prompt
        (strcat
          "\nDBDEBUG complete. Polylines="
          (itoa poly-count)
          ", holes="
          (itoa hole-count)
          ", recognized corners="
          (itoa corner-count)
          ", dogbones="
          (itoa dogbone-count)
          ", duplicates skipped="
          (itoa duplicate-count)
          "."
        )
      )
      (if (> skipped-open 0)
        (prompt (strcat "\nSkipped open/invalid polylines: " (itoa skipped-open) "."))
      )
      (if (> skipped-bulge 0)
        (prompt (strcat "\nSkipped polylines with arc bulges: " (itoa skipped-bulge) "."))
      )
      (if (and (> hole-count 0) (not *db-process-holes*))
        (prompt "\nHole outlines were detected but hole processing is disabled.")
      )
    )
    (prompt "\nNothing selected.")
  )
  (setq *error* olderr)
  (princ)
)

(defun db:process-dbauto-group (items / tagged item result patch patches all-patches
                                      poly-count hole-count corner-count dogbone-count
                                      duplicate-count rebuilt-count newent)
  (setq tagged (db:tag-holes items))
  (setq poly-count (length tagged))
  (setq hole-count 0)
  (setq corner-count 0)
  (setq dogbone-count 0)
  (setq duplicate-count 0)
  (setq rebuilt-count 0)
  (setq all-patches '())
  (foreach item tagged
    (if (cadddr item) (setq hole-count (1+ hole-count)))
    (setq result (db:build-patches item all-patches))
    (setq patches (car result))
    (setq all-patches (append all-patches patches))
    (setq corner-count (+ corner-count (cadr result)))
    (setq dogbone-count (+ dogbone-count (length patches)))
    (setq duplicate-count (+ duplicate-count (caddr result)))
    (if *db-debug-mode*
      (foreach patch patches (db:draw-debug-patch patch))
    )
    (if patches
      (progn
        (setq newent (db:rebuild-polyline item patches))
        (if newent
          (progn
            (setq rebuilt-count (1+ rebuilt-count))
            (if (not *db-keep-original*) (entdel (car item)))
          )
        )
      )
    )
  )
  (list
    (cons 'valid poly-count)
    (cons 'holes hole-count)
    (cons 'corners corner-count)
    (cons 'dogbones dogbone-count)
    (cons 'duplicates duplicate-count)
    (cons 'rebuilt rebuilt-count)
  )
)

(defun c:DBAUTO (/ olderr ss selection groups group stats skipped-open skipped-bulge
                   direct-count block-count skipped-blocks poly-count hole-count
                   corner-count dogbone-count duplicate-count rebuilt-count)
  (db:ensure-defaults)
  (setq olderr *error*)
  (defun *error* (msg)
    (db:end-undo)
    (setq *error* olderr)
    (if (and msg (/= msg "Function cancelled"))
      (prompt (strcat "\nError: " msg))
    )
    (princ)
  )
  (prompt "\nSelect closed LWPOLYLINE outlines or 1:1 block references. Editing a block updates all references.")
  (setq ss (ssget '((0 . "LWPOLYLINE,INSERT"))))
  (if ss
    (progn
      (db:start-undo)
      (if *db-debug-mode* (db:ensure-debug-layers))
      (setq selection (db:collect-dbauto-groups ss))
      (setq groups (cdr (assoc 'groups selection)))
      (setq direct-count (cdr (assoc 'direct-count selection)))
      (setq block-count (cdr (assoc 'block-count selection)))
      (setq skipped-blocks (cdr (assoc 'skipped-blocks selection)))
      (setq skipped-open (cdr (assoc 'skipped-open selection)))
      (setq skipped-bulge (cdr (assoc 'skipped-bulge selection)))
      (setq poly-count 0)
      (setq hole-count 0)
      (setq corner-count 0)
      (setq dogbone-count 0)
      (setq duplicate-count 0)
      (setq rebuilt-count 0)
      (foreach group groups
        (setq stats (db:process-dbauto-group (nth 2 group)))
        (setq poly-count (+ poly-count (cdr (assoc 'valid stats))))
        (setq hole-count (+ hole-count (cdr (assoc 'holes stats))))
        (setq corner-count (+ corner-count (cdr (assoc 'corners stats))))
        (setq dogbone-count (+ dogbone-count (cdr (assoc 'dogbones stats))))
        (setq duplicate-count (+ duplicate-count (cdr (assoc 'duplicates stats))))
        (setq rebuilt-count (+ rebuilt-count (cdr (assoc 'rebuilt stats))))
      )
      (db:end-undo)
      (if (> block-count 0) (command "_.REGEN"))
      (prompt
        (strcat
          "\nDBAUTO complete. Selected="
          (itoa (sslength ss))
          ", direct polylines="
          (itoa direct-count)
          ", block definitions="
          (itoa block-count)
          ", valid outlines="
          (itoa poly-count)
          ", skipped="
          (itoa (+ skipped-open skipped-bulge skipped-blocks))
          ", holes="
          (itoa hole-count)
          ", recognized corners="
          (itoa corner-count)
          ", dogbones="
          (itoa dogbone-count)
          ", duplicates skipped="
          (itoa duplicate-count)
          ", rebuilt polylines="
          (itoa rebuilt-count)
          "."
        )
      )
      (if (> skipped-open 0)
        (prompt (strcat "\nSkipped open/invalid polylines: " (itoa skipped-open) "."))
      )
      (if (> skipped-bulge 0)
        (prompt (strcat "\nSkipped polylines with arc bulges: " (itoa skipped-bulge) "."))
      )
      (if (> skipped-blocks 0)
        (prompt (strcat "\nSkipped scaled, unsupported, or empty block references: " (itoa skipped-blocks) "."))
      )
      (if (and (> hole-count 0) (not *db-process-holes*))
        (prompt "\nHole outlines were detected but hole processing is disabled.")
      )
    )
    (prompt "\nNothing selected.")
  )
  (setq *error* olderr)
  (princ)
)

;;; =========================================================================
;;; NESTING / PACKING MODULE  (V2.1-Nest)
;;; =========================================================================
;;; Arranges selected LWPOLYLINE / INSERT parts into a rectangular sheet
;;; using an AABB bottom-left packing algorithm.
;;; New commands: DBNSET (set gap), DBNEST (single sheet), DBNESTM (multi sheet).
;;; =========================================================================

;;; ---------------------------------------------------------------------------
;;; db:lwpoly-bbox  —  AABB for a LWPOLYLINE entity
;;; Returns (min-x min-y max-x max-y) or nil
;;; ---------------------------------------------------------------------------
(defun db:lwpoly-bbox (ename / data verts pts p minx miny maxx maxy)
  (setq data (db:lwpoly-data ename))
  (setq verts (cadr data))
  (if (null verts)
    nil
    (progn
      (setq pts (db:vertex-points verts))
      (setq p (car pts))
      (setq minx (db:x p))
      (setq miny (db:y p))
      (setq maxx minx)
      (setq maxy miny)
      (foreach p (cdr pts)
        (if (< (db:x p) minx) (setq minx (db:x p)))
        (if (< (db:y p) miny) (setq miny (db:y p)))
        (if (> (db:x p) maxx) (setq maxx (db:x p)))
        (if (> (db:y p) maxy) (setq maxy (db:y p)))
      )
      (list minx miny maxx maxy)
    )
  )
)

;;; ---------------------------------------------------------------------------
;;; db:insert-collect-pts  —  Recursively collect world-coordinate points
;;; from all LWPOLYLINE entities inside a block definition.
;;; sx, sy  = accumulated X/Y scale
;;; rot     = accumulated rotation (radians)
;;; insx, insy = accumulated insertion point offset
;;; ---------------------------------------------------------------------------
(defun db:insert-collect-pts (blockname sx sy rot insx insy
                              / bdef sub-en ed etype allpts
                                sub-bn sub-ins sub-sx sub-sy sub-rot
                                data verts v px py rx ry cos-r sin-r
                                nested-pts)
  (setq bdef (tblsearch "BLOCK" blockname))
  (if (not bdef)
    nil
    (progn
      (setq sub-en (cdr (assoc -2 bdef)))
      (setq allpts '())
      (setq cos-r (cos rot))
      (setq sin-r (sin rot))
      (while sub-en
        (setq ed (entget sub-en))
        (setq etype (cdr (assoc 0 ed)))
        (cond
          ;; LWPOLYLINE inside block: collect its vertices
          ((= etype "LWPOLYLINE")
            (setq data (db:lwpoly-data sub-en))
            (setq verts (cadr data))
            (foreach v verts
              (setq px (* (db:x (car v)) sx))
              (setq py (* (db:y (car v)) sy))
              ;; rotate
              (setq rx (- (* px cos-r) (* py sin-r)))
              (setq ry (+ (* px sin-r) (* py cos-r)))
              ;; translate
              (setq allpts (cons (list (+ rx insx) (+ ry insy) 0.0) allpts))
            )
          )
          ;; Nested INSERT: recurse
          ((= etype "INSERT")
            (setq sub-bn (cdr (assoc 2 ed)))
            (setq sub-ins (cdr (assoc 10 ed)))
            (setq sub-sx (cdr (assoc 41 ed)))
            (setq sub-sy (cdr (assoc 42 ed)))
            (setq sub-rot (cdr (assoc 50 ed)))
            (if (not sub-sx) (setq sub-sx 1.0))
            (if (not sub-sy) (setq sub-sy 1.0))
            (if (not sub-rot) (setq sub-rot 0.0))
            ;; The nested INSERT's local coords must be transformed through
            ;; the parent's scale+rotation first.
            (setq nested-pts
              (db:insert-collect-pts
                sub-bn
                (* sx sub-sx)
                (* sy sub-sy)
                (+ rot sub-rot)
                ;; Translate the nested insertion point through parent transform
                (+ insx
                   (- (* (* (db:x sub-ins) sx) cos-r)
                      (* (* (db:y sub-ins) sy) sin-r)))
                (+ insy
                   (+ (* (* (db:x sub-ins) sx) sin-r)
                      (* (* (db:y sub-ins) sy) cos-r)))
              )
            )
            (if nested-pts
              (setq allpts (append allpts nested-pts))
            )
          )
        )
        (setq sub-en (entnext sub-en))
      )
      allpts
    )
  )
)

;;; ---------------------------------------------------------------------------
;;; db:insert-bbox  —  AABB for an INSERT (block reference) entity
;;; Returns (min-x min-y max-x max-y) or nil
;;; ---------------------------------------------------------------------------
(defun db:insert-bbox (ename / ed blockname ins sx sy rot pts p minx miny maxx maxy)
  (setq ed (entget ename))
  (setq blockname (cdr (assoc 2 ed)))
  (setq ins (cdr (assoc 10 ed)))
  (setq sx (cdr (assoc 41 ed)))
  (setq sy (cdr (assoc 42 ed)))
  (setq rot (cdr (assoc 50 ed)))
  (if (not sx) (setq sx 1.0))
  (if (not sy) (setq sy 1.0))
  (if (not rot) (setq rot 0.0))
  (setq pts (db:insert-collect-pts blockname sx sy rot (db:x ins) (db:y ins)))
  (if (or (not pts) (null pts))
    (progn
      (prompt (strcat "\n警告: 块 \"" blockname "\" 内未找到 LWPOLYLINE，跳过。"))
      nil
    )
    (progn
      (setq p (car pts))
      (setq minx (db:x p))
      (setq miny (db:y p))
      (setq maxx minx)
      (setq maxy miny)
      (foreach p (cdr pts)
        (if (< (db:x p) minx) (setq minx (db:x p)))
        (if (< (db:y p) miny) (setq miny (db:y p)))
        (if (> (db:x p) maxx) (setq maxx (db:x p)))
        (if (> (db:y p) maxy) (setq maxy (db:y p)))
      )
      (list minx miny maxx maxy)
    )
  )
)

;;; ---------------------------------------------------------------------------
;;; AABB helper accessors
;;; ---------------------------------------------------------------------------
(defun db:bbox-width (bbox)
  (- (nth 2 bbox) (nth 0 bbox))
)

(defun db:bbox-height (bbox)
  (- (nth 3 bbox) (nth 1 bbox))
)

(defun db:bbox-area (bbox)
  (* (db:bbox-width bbox) (db:bbox-height bbox))
)

(defun db:bbox-overlaps (a b /)
  (not
    (or
      (<= (nth 2 a) (+ (nth 0 b) *db-eps*))
      (>= (nth 0 a) (- (nth 2 b) *db-eps*))
      (<= (nth 3 a) (+ (nth 1 b) *db-eps*))
      (>= (nth 1 a) (- (nth 3 b) *db-eps*))
    )
  )
)

(defun db:bbox-overlaps-any (bbox bboxes / found b)
  (setq found nil)
  (foreach b bboxes
    (if (db:bbox-overlaps bbox b)
      (setq found T)
    )
  )
  found
)

(defun db:bbox-conflicts-with-gap (a b gap /)
  (not
    (or
      (<= (nth 2 a) (+ (- (nth 0 b) gap) *db-eps*))
      (>= (nth 0 a) (- (+ (nth 2 b) gap) *db-eps*))
      (<= (nth 3 a) (+ (- (nth 1 b) gap) *db-eps*))
      (>= (nth 1 a) (- (+ (nth 3 b) gap) *db-eps*))
    )
  )
)

(defun db:bbox-make (x y w h)
  (list x y (+ x w) (+ y h))
)

(defun db:bbox-offset (bbox dx dy)
  (list
    (+ (nth 0 bbox) dx)
    (+ (nth 1 bbox) dy)
    (+ (nth 2 bbox) dx)
    (+ (nth 3 bbox) dy)
  )
)

(defun db:entity-in-parts-p (ename parts / found part)
  (setq found nil)
  (foreach part parts
    (if (eq ename (car part))
      (setq found T)
    )
  )
  found
)

(defun db:add-unique-number (value values / found v)
  (setq found nil)
  (foreach v values
    (if (<= (abs (- v value)) *db-eps*)
      (setq found T)
    )
  )
  (if found values (cons value values))
)

(defun db:sort-numbers-asc (values / sorted rest value inserted tmp result)
  (setq sorted '())
  (setq rest values)
  (while rest
    (setq value (car rest))
    (setq rest (cdr rest))
    (setq inserted nil)
    (setq tmp sorted)
    (setq result '())
    (while (and tmp (not inserted))
      (if (<= (car tmp) value)
        (progn
          (setq result (cons (car tmp) result))
          (setq tmp (cdr tmp))
        )
        (setq inserted T)
      )
    )
    (setq result (cons value result))
    (while tmp
      (setq result (cons (car tmp) result))
      (setq tmp (cdr tmp))
    )
    (setq sorted (reverse result))
  )
  sorted
)

(defun db:update-board-occupied (boards index occupied / result i board)
  (setq result '())
  (setq i 0)
  (foreach board boards
    (if (= i index)
      (setq result (cons (list (car board) occupied) result))
      (setq result (cons board result))
    )
    (setq i (1+ i))
  )
  (reverse result)
)

(defun db:sheet-region-has-entities-p (bbox / minpt maxpt ss)
  (setq minpt (list (nth 0 bbox) (nth 1 bbox) 0.0))
  (setq maxpt (list (nth 2 bbox) (nth 3 bbox) 0.0))
  (setq ss (ssget "_C" minpt maxpt))
  (if ss T nil)
)

;;; ---------------------------------------------------------------------------
;;; db:entity-aabb  —  Unified AABB entry point
;;; ---------------------------------------------------------------------------
(defun db:entity-aabb (ename / ed etype)
  (setq ed (entget ename))
  (setq etype (cdr (assoc 0 ed)))
  (cond
    ((= etype "LWPOLYLINE") (db:lwpoly-bbox ename))
    ((= etype "INSERT")     (db:insert-bbox ename))
    (T nil)
  )
)

;;; ---------------------------------------------------------------------------
;;; db:collect-nest-parts  —  Prompt user to select parts and compute AABBs
;;; Returns list of (ename bbox width height area entity-type)
;;; ---------------------------------------------------------------------------
(defun db:collect-nest-parts (/ ss i n en bbox w h a etype parts)
  (prompt "\n选择要排料的零件 (LWPOLYLINE 或 INSERT): ")
  (setq ss (ssget '((0 . "LWPOLYLINE,INSERT"))))
  (if (not ss)
    nil
    (progn
      (setq parts '())
      (setq i 0)
      (setq n (sslength ss))
      (while (< i n)
        (setq en (ssname ss i))
        (setq bbox (db:entity-aabb en))
        (if bbox
          (progn
            (setq w (db:bbox-width bbox))
            (setq h (db:bbox-height bbox))
            (setq a (db:bbox-area bbox))
            (setq etype (cdr (assoc 0 (entget en))))
            (setq parts (cons (list en bbox w h a etype) parts))
          )
          (prompt (strcat "\n警告: 第 " (itoa (1+ i)) " 个实体无法计算 AABB，已跳过。"))
        )
        (setq i (1+ i))
      )
      (reverse parts)
    )
  )
)

;;; ---------------------------------------------------------------------------
;;; db:select-sheet  —  Prompt user to pick a rectangular sheet boundary
;;; Returns (ename bbox) or nil
;;; ---------------------------------------------------------------------------
(defun db:select-sheet (/ sel en ed etype data verts pts n closed bbox)
  (setq sel (entsel "\n请选择板框 (矩形闭合多段线): "))
  (if (not sel)
    (progn
      (prompt "\n未选择板框。")
      nil
    )
    (progn
      (setq en (car sel))
      (setq ed (entget en))
      (setq etype (cdr (assoc 0 ed)))
      (if (/= etype "LWPOLYLINE")
        (progn
          (prompt "\n错误: 选择的不是 LWPOLYLINE。")
          nil
        )
        (progn
          (setq data (db:lwpoly-data en))
          (setq closed (car data))
          (setq verts (cadr data))
          (setq n (length verts))
          (if (not closed)
            (progn
              (prompt "\n错误: 板框必须是闭合多段线。")
              nil
            )
            (if (/= n 4)
              (progn
                (prompt (strcat "\n错误: 板框必须是 4 个顶点的矩形，当前有 " (itoa n) " 个顶点。"))
                nil
              )
              (progn
                (setq bbox (db:lwpoly-bbox en))
                (prompt
                  (strcat
                    "\n板框尺寸: "
                    (rtos (db:bbox-width bbox) 2 2)
                    " x "
                    (rtos (db:bbox-height bbox) 2 2)
                  )
                )
                (list en bbox)
              )
            )
          )
        )
      )
    )
  )
)

;;; ---------------------------------------------------------------------------
;;; db:collect-sheet-obstacles  —  Existing sheet entities used as obstacles
;;; ---------------------------------------------------------------------------
(defun db:collect-sheet-obstacles (sheet-en sheet-bbox parts
                                    / minpt maxpt ss i n en bbox obstacles)
  (setq minpt (list (nth 0 sheet-bbox) (nth 1 sheet-bbox) 0.0))
  (setq maxpt (list (nth 2 sheet-bbox) (nth 3 sheet-bbox) 0.0))
  (setq ss (ssget "_C" minpt maxpt '((0 . "LWPOLYLINE,INSERT"))))
  (setq obstacles '())
  (if ss
    (progn
      (setq i 0)
      (setq n (sslength ss))
      (while (< i n)
        (setq en (ssname ss i))
        (if (and (not (eq en sheet-en))
                 (not (db:entity-in-parts-p en parts)))
          (progn
            (setq bbox (db:entity-aabb en))
            (if (and bbox (db:bbox-overlaps bbox sheet-bbox))
              (setq obstacles (cons bbox obstacles))
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (reverse obstacles)
)

;;; ---------------------------------------------------------------------------
;;; db:sort-by-area-desc  —  Sort parts by area (5th element) descending
;;; Simple insertion sort for AutoLISP compatibility
;;; ---------------------------------------------------------------------------
(defun db:sort-by-area-desc (parts / sorted rest item inserted tmp result)
  (setq sorted '())
  (setq rest parts)
  (while rest
    (setq item (car rest))
    (setq rest (cdr rest))
    ;; Insert item into sorted list at the correct position
    (setq inserted nil)
    (setq tmp '())
    (setq result '())
    (setq tmp sorted)
    (while (and tmp (not inserted))
      (if (>= (nth 4 (car tmp)) (nth 4 item))
        (progn
          (setq result (cons (car tmp) result))
          (setq tmp (cdr tmp))
        )
        (setq inserted T)
      )
    )
    (setq result (cons item result))
    (while tmp
      (setq result (cons (car tmp) result))
      (setq tmp (cdr tmp))
    )
    (setq sorted (reverse result))
  )
  sorted
)

(defun db:part-orientations (part / w h)
  (setq w (nth 2 part))
  (setq h (nth 3 part))
  (if (<= (abs (- w h)) *db-eps*)
    (list (list 0 w h))
    (list (list 0 w h) (list 90 h w))
  )
)

(defun db:candidate-xs (sheet-bbox occupied gap / values b x maxx)
  (setq values (list (nth 0 sheet-bbox)))
  (setq maxx (nth 2 sheet-bbox))
  (foreach b occupied
    (setq x (+ (nth 2 b) gap))
    (if (<= x (+ maxx *db-eps*))
      (setq values (db:add-unique-number x values))
    )
  )
  (db:sort-numbers-asc values)
)

(defun db:candidate-ys (sheet-bbox occupied gap / values b y maxy)
  (setq values (list (nth 1 sheet-bbox)))
  (setq maxy (nth 3 sheet-bbox))
  (foreach b occupied
    (setq y (+ (nth 3 b) gap))
    (if (<= y (+ maxy *db-eps*))
      (setq values (db:add-unique-number y values))
    )
  )
  (db:sort-numbers-asc values)
)

(defun db:placement-blocked-p (candidate occupied gap / blocked b)
  (setq blocked nil)
  (foreach b occupied
    (if (db:bbox-conflicts-with-gap candidate b gap)
      (setq blocked T)
    )
  )
  blocked
)

(defun db:find-placement (part sheet-bbox gap occupied
                          / orientations orient angle pw ph xs ys x y candidate placement)
  (setq placement nil)
  (setq orientations (db:part-orientations part))
  (setq xs (db:candidate-xs sheet-bbox occupied gap))
  (setq ys (db:candidate-ys sheet-bbox occupied gap))
  (foreach y ys
    (foreach x xs
      (foreach orient orientations
        (if (not placement)
          (progn
            (setq angle (car orient))
            (setq pw (cadr orient))
            (setq ph (caddr orient))
            (setq candidate (db:bbox-make x y pw ph))
            (if (and
                  (<= (nth 0 sheet-bbox) (+ (nth 0 candidate) *db-eps*))
                  (<= (nth 1 sheet-bbox) (+ (nth 1 candidate) *db-eps*))
                  (<= (nth 2 candidate) (+ (nth 2 sheet-bbox) *db-eps*))
                  (<= (nth 3 candidate) (+ (nth 3 sheet-bbox) *db-eps*))
                  (not (db:placement-blocked-p candidate occupied gap)))
              (setq placement (list x y angle candidate))
            )
          )
        )
      )
    )
  )
  placement
)

;;; ---------------------------------------------------------------------------
;;; db:bottom-left-pack  —  AABB bottom-left packer with obstacles and rotation
;;; parts      = list of (ename bbox width height area entity-type)
;;; obstacles  = existing sheet AABBs that new parts must avoid
;;; Returns list of (ename target-x target-y angle placed)
;;; ---------------------------------------------------------------------------
(defun db:bottom-left-pack (parts sheet-bbox gap obstacles
                            / occupied results part placement placed tx ty chosen-angle candidate)
  (setq occupied obstacles)
  (setq results '())
  (foreach part parts
    (setq placed nil)
    (setq tx 0.0)
    (setq ty 0.0)
    (setq chosen-angle 0)
    (setq placement (db:find-placement part sheet-bbox gap occupied))
    (if placement
      (progn
        (setq placed T)
        (setq tx (car placement))
        (setq ty (cadr placement))
        (setq chosen-angle (caddr placement))
        (setq candidate (cadddr placement))
        (setq occupied (cons candidate occupied))
      )
    )
    (setq results (cons (list (car part) tx ty chosen-angle placed) results))
  )
  (reverse results)
)

(defun db:sheet-bbox-at-index (template-bbox sheet-gap index / step)
  (setq step (+ (db:bbox-width template-bbox) sheet-gap))
  (db:bbox-offset template-bbox (* index step) 0.0)
)

(defun db:find-empty-sheet-bbox (template-bbox sheet-gap occupied-sheet-bboxes start-index
                                  / index candidate found)
  (setq index start-index)
  (setq found nil)
  (while (not found)
    (setq candidate (db:sheet-bbox-at-index template-bbox sheet-gap index))
    (if (or (db:bbox-overlaps-any candidate occupied-sheet-bboxes)
            (db:sheet-region-has-entities-p candidate))
      (setq index (1+ index))
      (setq found T)
    )
  )
  (list index candidate)
)

(defun db:multi-sheet-pack (parts template-bbox gap sheet-gap initial-obstacles
                            / boards results part placed board-index board placement
                              occupied candidate new-index new-bbox new-sheet occupied-sheet-bboxes)
  (setq boards (list (list template-bbox initial-obstacles)))
  (setq occupied-sheet-bboxes (list template-bbox))
  (setq results '())
  (foreach part parts
    (setq placed nil)
    (setq board-index 0)
    (foreach board boards
      (if (not placed)
        (progn
          (setq placement (db:find-placement part (car board) gap (cadr board)))
          (if placement
            (progn
              (setq placed T)
              (setq occupied (cadr board))
              (setq candidate (cadddr placement))
              (setq boards (db:update-board-occupied boards board-index (cons candidate occupied)))
              (setq results
                (cons
                  (list
                    (car part)
                    (car placement)
                    (cadr placement)
                    (caddr placement)
                    board-index
                    T
                  )
                  results
                )
              )
            )
          )
        )
      )
      (setq board-index (1+ board-index))
    )
    (if (not placed)
      (progn
        (setq new-sheet (db:find-empty-sheet-bbox template-bbox sheet-gap occupied-sheet-bboxes (length boards)))
        (setq new-index (car new-sheet))
        (setq new-bbox (cadr new-sheet))
        (setq placement (db:find-placement part new-bbox gap '()))
        (if placement
          (progn
            (setq candidate (cadddr placement))
            (setq occupied-sheet-bboxes (append occupied-sheet-bboxes (list new-bbox)))
            (setq boards (append boards (list (list new-bbox (list candidate)))))
            (setq results
              (cons
                (list
                  (car part)
                  (car placement)
                  (cadr placement)
                  (caddr placement)
                  new-index
                  T
                )
                results
              )
            )
          )
          (setq results (cons (list (car part) 0.0 0.0 0 new-index nil) results))
        )
      )
    )
  )
  (list (reverse results) boards)
)

;;; ---------------------------------------------------------------------------
;;; db:shelf-pack  —  Shelf (layer) packing algorithm
;;; parts      = list of (ename bbox width height area entity-type)
;;; sheet-bbox = (min-x min-y max-x max-y)
;;; gap        = minimum spacing between parts
;;;
;;; Parts can touch the sheet edges (no inset). Gap is only between parts.
;;;
;;; Returns list of (ename target-x target-y placed)
;;;   placed = T or nil
;;; ---------------------------------------------------------------------------
(defun db:shelf-pack (parts sheet-bbox gap
                      / sheet-minx sheet-miny sheet-w sheet-h
                        shelf-x shelf-y shelf-h
                        results part pw ph tx ty placed first-in-row)
  (setq sheet-minx (nth 0 sheet-bbox))
  (setq sheet-miny (nth 1 sheet-bbox))
  (setq sheet-w (db:bbox-width sheet-bbox))
  (setq sheet-h (db:bbox-height sheet-bbox))
  (setq shelf-x 0.0)
  (setq shelf-y 0.0)
  (setq shelf-h 0.0)
  (setq results '())
  (setq first-in-row T)
  (foreach part parts
    (setq pw (nth 2 part))  ; width
    (setq ph (nth 3 part))  ; height
    (setq placed nil)
    ;; Check if part fits in the sheet at all
    (if (and (<= pw (+ sheet-w *db-eps*))
             (<= ph (+ sheet-h *db-eps*)))
      (progn
        ;; Check if part fits in current row
        ;; If not first in row, we need gap before this part
        (if (and (not first-in-row)
                 (> (+ shelf-x gap pw) (+ sheet-w *db-eps*)))
          ;; Need new row
          (progn
            (setq shelf-y (+ shelf-y shelf-h gap))
            (setq shelf-x 0.0)
            (setq shelf-h 0.0)
            (setq first-in-row T)
          )
        )
        ;; If first in row, check width directly (no gap prefix)
        (if (and first-in-row
                 (> pw (+ sheet-w *db-eps*)))
          nil  ;; part too wide, can't place
          (progn
            ;; Check vertical fit
            (if (<= (+ shelf-y ph) (+ sheet-h *db-eps*))
              (progn
                (setq tx (+ sheet-minx shelf-x))
                (setq ty (+ sheet-miny shelf-y))
                (setq placed T)
                ;; Update shelf tracking
                (if (> ph shelf-h) (setq shelf-h ph))
                (if first-in-row
                  (progn
                    (setq shelf-x (+ shelf-x pw))
                    (setq first-in-row nil)
                  )
                  (setq shelf-x (+ shelf-x gap pw))
                )
              )
            )
          )
        )
      )
    )
    (if (not placed)
      (setq tx 0.0 ty 0.0)
    )
    (setq results (cons (list (car part) tx ty placed) results))
  )
  (reverse results)
)

;;; ---------------------------------------------------------------------------
;;; db:move-entity-to  —  Move an entity from one point to another
;;; ---------------------------------------------------------------------------
(defun db:move-entity-to (ename from-pt to-pt)
  (command "_.MOVE" ename "" from-pt to-pt)
)

(defun db:rotate-entity-90 (ename bbox / base)
  (setq base (list (nth 0 bbox) (nth 1 bbox) 0.0))
  (command "_.ROTATE" ename "" base "90")
)

(defun db:copy-sheet-frame (sheet-en source-bbox target-bbox / from-pt to-pt copied)
  (setq from-pt (list (nth 0 source-bbox) (nth 1 source-bbox) 0.0))
  (setq to-pt (list (nth 0 target-bbox) (nth 1 target-bbox) 0.0))
  (command "_.COPY" sheet-en "" from-pt to-pt)
  (setq copied (entlast))
  copied
)

(defun db:place-nested-entity (en tx ty angle / bbox from-pt to-pt)
  (setq bbox (db:entity-aabb en))
  (if (= angle 90)
    (progn
      (db:rotate-entity-90 en bbox)
      (setq bbox (db:entity-aabb en))
    )
  )
  (setq from-pt (list (nth 0 bbox) (nth 1 bbox) 0.0))
  (setq to-pt (list tx ty 0.0))
  (db:move-entity-to en from-pt to-pt)
)

;;; ---------------------------------------------------------------------------
;;; c:DBNSET  —  Set nesting gap parameter
;;; ---------------------------------------------------------------------------
(defun c:DBNSET (/ g)
  (prompt (strcat "\n当前排料间距: " (rtos *db-nest-gap* 2 2) " mm"))
  (setq g (getreal (strcat "\n输入新的排料间距 <" (rtos *db-nest-gap* 2 2) ">: ")))
  (if (and g (>= g 0.0))
    (setq *db-nest-gap* g)
  )
  (prompt (strcat "\n排料间距已设为: " (rtos *db-nest-gap* 2 2) " mm"))
  (princ)
)

;;; ---------------------------------------------------------------------------
;;; c:DBNEST  —  Main nesting command
;;; ---------------------------------------------------------------------------
(defun c:DBNEST (/ olderr parts sheet sheet-en sheet-bbox obstacles sorted results
                   total-count placed-count remain-count
                   r en tx ty angle placed bbox from-pt to-pt)
  (setq olderr *error*)
  (defun *error* (msg)
    (db:end-undo)
    (setq *error* olderr)
    (if (and msg (/= msg "Function cancelled"))
      (prompt (strcat "\nError: " msg))
    )
    (princ)
  )
  (db:start-undo)
  ;; Step 1: Collect parts
  (setq parts (db:collect-nest-parts))
  (if (or (not parts) (null parts))
    (progn
      (prompt "\n未选择任何有效零件。")
      (db:end-undo)
      (setq *error* olderr)
      (princ)
    )
    (progn
      ;; Step 2: Select sheet
      (setq sheet (db:select-sheet))
      (if (not sheet)
        (progn
          (prompt "\n板框选择失败，操作取消。")
          (db:end-undo)
          (setq *error* olderr)
          (princ)
        )
        (progn
          (setq sheet-en (car sheet))
          (setq sheet-bbox (cadr sheet))
          (setq obstacles (db:collect-sheet-obstacles sheet-en sheet-bbox parts))
          ;; Step 3: Sort by area descending
          (setq sorted (db:sort-by-area-desc parts))
          (prompt (strcat "\n开始排料... 零件数: " (itoa (length sorted))
                          ", 已占用: " (itoa (length obstacles))
                          ", 间距: " (rtos *db-nest-gap* 2 2)))
          ;; Step 4: Run obstacle-aware packing
          (setq results (db:bottom-left-pack sorted sheet-bbox *db-nest-gap* obstacles))
          ;; Step 5: Move placed parts
          (setq total-count (length results))
          (setq placed-count 0)
          (setq remain-count 0)
          (foreach r results
            (setq en (car r))
            (setq tx (cadr r))
            (setq ty (caddr r))
            (setq angle (cadddr r))
            (setq placed (nth 4 r))
            (if placed
              (progn
                (setq bbox (db:entity-aabb en))
                (if (= angle 90)
                  (progn
                    (db:rotate-entity-90 en bbox)
                    (setq bbox (db:entity-aabb en))
                  )
                )
                (setq from-pt (list (nth 0 bbox) (nth 1 bbox) 0.0))
                (setq to-pt (list tx ty 0.0))
                (db:move-entity-to en from-pt to-pt)
                (setq placed-count (1+ placed-count))
              )
              (setq remain-count (1+ remain-count))
            )
          )
          ;; Step 6: Report
          (prompt
            (strcat
              "\nDBNEST 完成。共 " (itoa total-count)
              " 个零件，已排入 " (itoa placed-count)
              " 个，剩余 " (itoa remain-count)
              " 个未排入。"
            )
          )
          (db:end-undo)
          (setq *error* olderr)
          (princ)
        )
      )
    )
  )
)

;;; ---------------------------------------------------------------------------
;;; c:DBNESTM  —  Multi-sheet nesting command
;;; ---------------------------------------------------------------------------
(defun c:DBNESTM (/ olderr parts sheet sheet-en sheet-bbox obstacles sorted
                    sheet-gap packed results boards board-count
                    total-count placed-count remain-count copy-index board
                    r en tx ty angle placed gap-input)
  (setq olderr *error*)
  (defun *error* (msg)
    (db:end-undo)
    (setq *error* olderr)
    (if (and msg (/= msg "Function cancelled"))
      (prompt (strcat "\nError: " msg))
    )
    (princ)
  )
  (db:start-undo)
  (setq parts (db:collect-nest-parts))
  (if (or (not parts) (null parts))
    (progn
      (prompt "\n未选择任何有效零件。")
      (db:end-undo)
      (setq *error* olderr)
      (princ)
    )
    (progn
      (setq sheet (db:select-sheet))
      (if (not sheet)
        (progn
          (prompt "\n板框选择失败，操作取消。")
          (db:end-undo)
          (setq *error* olderr)
          (princ)
        )
        (progn
          (setq sheet-en (car sheet))
          (setq sheet-bbox (cadr sheet))
          (setq gap-input
            (getreal
              (strcat
                "\n输入复制板框之间的水平间距 <"
                (rtos *db-nest-sheet-gap* 2 2)
                ">: "
              )
            )
          )
          (if (and gap-input (>= gap-input 0.0))
            (setq *db-nest-sheet-gap* gap-input)
          )
          (setq sheet-gap *db-nest-sheet-gap*)
          (setq obstacles (db:collect-sheet-obstacles sheet-en sheet-bbox parts))
          (setq sorted (db:sort-by-area-desc parts))
          (prompt
            (strcat
              "\n开始多板排料... 零件数: " (itoa (length sorted))
              ", 首板已占用: " (itoa (length obstacles))
              ", 零件间距: " (rtos *db-nest-gap* 2 2)
              ", 板框间距: " (rtos sheet-gap 2 2)
            )
          )
          (setq packed (db:multi-sheet-pack sorted sheet-bbox *db-nest-gap* sheet-gap obstacles))
          (setq results (car packed))
          (setq boards (cadr packed))
          (setq board-count (length boards))
          (setq copy-index 1)
          (while (< copy-index board-count)
            (setq board (nth copy-index boards))
            (db:copy-sheet-frame sheet-en sheet-bbox (car board))
            (setq copy-index (1+ copy-index))
          )
          (setq total-count (length results))
          (setq placed-count 0)
          (setq remain-count 0)
          (foreach r results
            (setq en (car r))
            (setq tx (cadr r))
            (setq ty (caddr r))
            (setq angle (cadddr r))
            (setq placed (nth 5 r))
            (if placed
              (progn
                (db:place-nested-entity en tx ty angle)
                (setq placed-count (1+ placed-count))
              )
              (setq remain-count (1+ remain-count))
            )
          )
          (prompt
            (strcat
              "\nDBNESTM 完成。共 " (itoa total-count)
              " 个零件，已排入 " (itoa placed-count)
              " 个，剩余 " (itoa remain-count)
              " 个未排入，使用板框 " (itoa board-count)
              " 个。"
            )
          )
          (db:end-undo)
          (setq *error* olderr)
          (princ)
        )
      )
    )
  )
)

(prompt (strcat "\nDogbone plugin " *db-version* " loaded. Commands: DBSET, DB1, DBDEBUG, DBAUTO, DBADD, DBRESTORE, DBRESTOREALL, DBNSET, DBNEST, DBNESTM."))
(princ)
