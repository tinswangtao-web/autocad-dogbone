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
;;;   DBAUTO  - Rebuild selected closed LWPOLYLINE entities with C 45-degree dogbones.
;;;
;;; Production mode creates a new closed LWPOLYLINE and deletes the original
;;; only after the replacement entity is created successfully.

(setq *db-version* "V2.1")
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

(defun db:make-lwpolyline (layer color ltype lweight vertices / header data v)
  (setq header
    (list
      '(0 . "LWPOLYLINE")
      '(100 . "AcDbEntity")
      (cons 8 layer)
    )
  )
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

(defun db:collect-selection (ss / i en data ed verts pts area items skipped-open skipped-bulge layer color ltype lweight)
  (setq i 0)
  (setq items '())
  (setq skipped-open 0)
  (setq skipped-bulge 0)
  (while (< i (sslength ss))
    (setq en (ssname ss i))
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
    (setq i (1+ i))
  )
  (list (reverse items) skipped-open skipped-bulge)
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

(defun db:rebuild-polyline (item patches / pts layer color ltype lweight n i patch vertices)
  (setq pts (cadr item))
  (setq layer (nth 4 item))
  (if (not layer) (setq layer "0"))
  (setq color (nth 5 item))
  (setq ltype (nth 6 item))
  (setq lweight (nth 7 item))
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
    (db:make-lwpolyline layer color ltype lweight vertices)
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

(defun c:DBAUTO (/ olderr ss collected items skipped-open skipped-bulge tagged
                   item result patch patches all-patches poly-count hole-count corner-count
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
  (prompt "\nSelect closed LWPOLYLINE outlines for C 45-degree dogbone rebuild.")
  (setq ss (ssget '((0 . "LWPOLYLINE"))))
  (if ss
    (progn
      (db:start-undo)
      (if *db-debug-mode* (db:ensure-debug-layers))
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
          (foreach patch patches
            (db:draw-debug-patch patch)
          )
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
      (db:end-undo)
      (prompt
        (strcat
          "\nDBAUTO complete. Selected="
          (itoa (sslength ss))
          ", valid="
          (itoa poly-count)
          ", skipped="
          (itoa (+ skipped-open skipped-bulge))
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
      (if (and (> hole-count 0) (not *db-process-holes*))
        (prompt "\nHole outlines were detected but hole processing is disabled.")
      )
    )
    (prompt "\nNothing selected.")
  )
  (setq *error* olderr)
  (princ)
)

(prompt (strcat "\nDogbone plugin " *db-version* " loaded. Commands: DBSET, DB1, DBDEBUG, DBAUTO, DBADD, DBRESTORE, DBRESTOREALL."))
(princ)
