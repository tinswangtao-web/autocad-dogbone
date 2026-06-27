;;; dogbone.lsp
;;; AutoCAD for Mac compatible AutoLISP dogbone helper.
;;; Stable version: V2.1
;;;
;;; Commands:
;;;   DBVER   - Show loaded plugin version.
;;;   DBSET   - Set tool diameter and whether contained hole outlines are handled.
;;;   DB1     - Draw A/B/C single-corner test geometry for review.
;;;   DBDEBUG - Draw debug markers for recognized dogbone corners.
;;;   DBADD   - Add dogbones to selected sharp corners.
;;;   DBRESTORE - Restore selected dogbones back to sharp corners.
;;;   DBRESTOREALL - Restore all dogbones in selected polylines.
;;;   DBAUTO  - Rebuild selected closed LWPOLYLINE entities or 1:1 block definitions
;;;             with C 45-degree dogbones.
;;;   DBNSET  - Set nesting gap and sheet edge margin.
;;;   DBNEST  - Pack selected parts across copied sheet frames.
;;;   DBNESTM - Compatibility alias for multi-sheet nesting.
;;;
;;; Production mode creates a new closed LWPOLYLINE and deletes the original
;;; only after the replacement entity is created successfully.

(setq *db-version* "V2.1-Nest-Compact")
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
(setq *db-circle-min-vertices* 24)
(setq *db-circle-radius-tol* 0.001)
(setq *db-nest-gap* 6.0)
(setq *db-nest-edge-margin* 2.0)
(setq *db-nest-sheet-gap* 50.0)
(setq *db-last-nest-raw-count* 0)
(setq *db-last-nest-group-count* 0)
(setq *db-last-tail-compact-status* "SKIPPED")
(setq *db-last-tail-compact-before* 0)
(setq *db-last-tail-compact-after* 0)
(setq *db-last-tail-compact-count* 0)

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
  (if (not *db-circle-min-vertices*) (setq *db-circle-min-vertices* 24))
  (if (not *db-circle-radius-tol*) (setq *db-circle-radius-tol* 0.001))
  (if (not *db-nest-gap*) (setq *db-nest-gap* 6.0))
  (if (not *db-nest-edge-margin*) (setq *db-nest-edge-margin* 2.0))
  (if (not *db-nest-sheet-gap*) (setq *db-nest-sheet-gap* 50.0))
  (if (not (boundp '*db-last-nest-raw-count*)) (setq *db-last-nest-raw-count* 0))
  (if (not (boundp '*db-last-nest-group-count*)) (setq *db-last-nest-group-count* 0))
  (if (not (boundp '*db-last-tail-compact-status*)) (setq *db-last-tail-compact-status* "SKIPPED"))
  (if (not (boundp '*db-last-tail-compact-before*)) (setq *db-last-tail-compact-before* 0))
  (if (not (boundp '*db-last-tail-compact-after*)) (setq *db-last-tail-compact-after* 0))
  (if (not (boundp '*db-last-tail-compact-count*)) (setq *db-last-tail-compact-count* 0))
)

(defun c:DBVER ()
  (prompt
    (strcat
      "\nDogbone plugin version: " *db-version*
      "\nLoaded commands include: DBVER, DBSET, DB1, DBDEBUG, DBAUTO, DBADD, DBRESTORE, DBRESTOREALL, DBNSET, DBNEST, DBNESTM."
    )
  )
  (princ)
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

;;; Fallback where one adjacent segment is shorter than the standard C dogbone
;;; trim. Use the short segment endpoint as one circle point, solve the other
;;; point on the long segment so the chord is 2R, and keep the arc close to the
;;; original corner.
(defun db:create-short-leg-c-patch (p0 p1 p2 radius source-index / v1 v2 len1 len2 theta chord cos-theta sin-theta short-len long-len short-dir long-dir disc long-trim center start end bulge)
  (setq v1 (db:norm (db:sub p0 p1)))
  (setq v2 (db:norm (db:sub p2 p1)))
  (if (and v1 v2)
    (progn
      (setq theta (db:acos (db:dot v1 v2)))
      (setq len1 (db:distance p0 p1))
      (setq len2 (db:distance p2 p1))
      (setq chord (* 2.0 radius))
      (setq cos-theta (cos theta))
      (setq sin-theta (sin theta))
      (if (< len1 len2)
        (progn
          (setq short-len len1)
          (setq long-len len2)
          (setq short-dir v1)
          (setq long-dir v2)
        )
        (progn
          (setq short-len len2)
          (setq long-len len1)
          (setq short-dir v2)
          (setq long-dir v1)
        )
      )
      (setq disc (- (* chord chord) (* short-len short-len sin-theta sin-theta)))
      (if (and
            (> (abs (- len1 len2)) *db-eps*)
            (> disc *db-eps*)
            (< short-len chord)
          )
        (progn
          (setq long-trim (+ (* short-len cos-theta) (sqrt disc)))
          (if (and (> long-trim *db-eps*) (<= long-trim (+ long-len *db-eps*)))
            (progn
              (if (< len1 len2)
                (progn
                  (setq start p0)
                  (setq end (db:add p1 (db:mul long-dir long-trim)))
                )
                (progn
                  (setq start (db:add p1 (db:mul long-dir long-trim)))
                  (setq end p2)
                )
              )
              (setq center (db:mul (db:add start end) 0.5))
              (setq bulge (db:arc-bulge-near-corner center radius start end p1))
              (db:make-production-patch "circle-short-leg" source-index p1 center start end radius bulge theta "C Short-Leg")
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
;;; Bulge belongs to the segment starting at that point. DBAUTO preserves
;;; untouched bulges but only applies the current C patch to sharp line-line
;;; dogbone candidates.
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

;;; Confirm that vertices traverse the fitted circle once in one direction.
(defun db:circle-ordered-p (pts center / n i p q angle step-sign direction total valid)
  (setq n (length pts))
  (setq i 0)
  (setq direction nil)
  (setq total 0.0)
  (setq valid T)
  (while (and valid (< i n))
    (setq p (nth i pts))
    (setq q (nth (rem (1+ i) n) pts))
    (if (<= (db:distance p q) *db-eps*)
      (setq valid nil)
      (progn
        (setq angle (db:signed-angle (db:sub p center) (db:sub q center)))
        (if (<= (abs angle) *db-eps*)
          (setq valid nil)
          (progn
            (setq step-sign (if (> angle 0.0) 1.0 -1.0))
            (if (not direction)
              (setq direction step-sign)
              (if (/= step-sign direction) (setq valid nil))
            )
            (setq total (+ total angle))
          )
        )
      )
    )
    (setq i (1+ i))
  )
  (and valid (<= (abs (- (abs total) (* 2.0 pi))) 0.01))
)

;;; Recognize an even, symmetric straight-segment outline whose opposite vertex
;;; pairs define one center and whose vertices lie on one circle.
;;; The caller is responsible for checking closure and existing bulges.
(defun db:segmented-circle-data (pts / n half center radius max-error max-center-error
                                      i p q pair-center error center-error)
  (setq n (length pts))
  (if (or
        (< (length pts) *db-circle-min-vertices*)
        (= 1 (rem n 2))
      )
    nil
    (progn
      (setq half (fix (/ n 2)))
      (setq center (db:mul (db:add (nth 0 pts) (nth half pts)) 0.5))
      (setq radius (db:distance center (nth 0 pts)))
      (if (<= radius *db-eps*)
        nil
        (progn
          (setq i 0)
          (setq max-error 0.0)
          (setq max-center-error 0.0)
          (while (< i half)
            (setq p (nth i pts))
            (setq q (nth (+ i half) pts))
            (setq pair-center (db:mul (db:add p q) 0.5))
            (setq center-error (db:distance pair-center center))
            (if (> center-error (* radius *db-circle-radius-tol*))
              (setq max-center-error center-error)
            )
            (setq i (1+ i))
          )
          (foreach p pts
            (setq error (abs (- (db:distance center p) radius)))
            (if (> error max-error) (setq max-error error))
          )
          (if (or
                (> max-error (* radius *db-circle-radius-tol*))
                (> max-center-error (* radius *db-circle-radius-tol*))
                (not (db:circle-ordered-p pts center))
              )
            nil
            (list center radius)
          )
        )
      )
    )
  )
)

;;; Create a true CIRCLE for a directly selected segmented-circle item.
(defun db:make-circle-from-item (item circle-data / layer color ltype lweight center radius data)
  (setq layer (nth 4 item))
  (setq color (nth 5 item))
  (setq ltype (nth 6 item))
  (setq lweight (nth 7 item))
  (setq center (car circle-data))
  (setq radius (cadr circle-data))
  (setq data
    (list
      '(0 . "CIRCLE")
      '(100 . "AcDbEntity")
      (cons 8 layer)
    )
  )
  (if color (setq data (append data (list (cons 62 color)))))
  (if ltype (setq data (append data (list (cons 6 ltype)))))
  (if lweight (setq data (append data (list (cons 370 lweight)))))
  (setq data
    (append
      data
      (list
        '(100 . "AcDbCircle")
        (cons 10 (db:pt2 center))
        (cons 40 radius)
      )
    )
  )
  (entmakex data)
)

;;; Exact full-circle LWPOLYLINE representation for in-place block updates.
(defun db:circle-polyline-vertices (center radius area / start end bulge)
  (setq start (list (+ (db:x center) radius) (db:y center) 0.0))
  (setq end (list (- (db:x center) radius) (db:y center) 0.0))
  (setq bulge (if (> area 0.0) 1.0 -1.0))
  (list (list start bulge) (list end bulge))
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
  (command-s "_.UNDO" "_Begin")
)

(defun db:end-undo ()
  (command-s "_.UNDO" "_End")
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

(defun db:collect-entities (entities / en data ed verts pts area circle-data items skipped-open skipped-bulge layer color ltype lweight)
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
      (T
        (setq pts (db:vertex-points verts))
        (setq area (db:poly-area pts))
        (if (> (abs area) *db-eps*)
          (progn
            (setq circle-data (if (db:has-bulge verts) nil (db:segmented-circle-data pts)))
            (setq layer (cdr (assoc 8 ed)))
            (setq color (cdr (assoc 62 ed)))
            (setq ltype (cdr (assoc 6 ed)))
            (setq lweight (cdr (assoc 370 ed)))
            (setq items (cons (list en pts area nil layer color ltype lweight verts circle-data) items))
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

(defun db:item-circle-data (item)
  (nth 9 item)
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

(defun db:auto-corner-candidate-p (verts idx p0 p1 p2 area is-hole)
  (and
    (db:sharp-corner-p verts idx)
    (db:needs-dogbone p0 p1 p2 area is-hole)
  )
)

(defun db:patch-before-bulge (patch / found)
  (setq found (assoc 'before-bulge patch))
  (if found (cdr found) 0.0)
)

(defun db:patch-after-bulge (patch / found)
  (setq found (assoc 'after-bulge patch))
  (if found (cdr found) 0.0)
)

(defun db:attach-source-bulges (patch verts idx / n prev-bulge this-bulge)
  (setq n (length verts))
  (setq prev-bulge (db:vertex-bulge verts (rem (+ idx n -1) n)))
  (setq this-bulge (db:vertex-bulge verts idx))
  (if patch
    (append
      patch
      (list
        (cons 'before-bulge prev-bulge)
        (cons 'after-bulge this-bulge)
      )
    )
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

(defun db:create-c-or-short-leg-patch (p0 p1 p2 radius source-index / patch)
  (setq patch (db:create-c-patch p0 p1 p2 radius source-index))
  (if (not patch)
    (setq patch (db:create-short-leg-c-patch p0 p1 p2 radius source-index))
  )
  patch
)

(defun db:create-patch (p0 p1 p2 index / r)
  (setq r (db:radius))
  (cond
    ((= *db-dogbone-type* "C")
      (db:create-c-or-short-leg-patch p0 p1 p2 r index)
    )
    (T
      (db:create-c-or-short-leg-patch p0 p1 p2 r index)
    )
  )
)

(defun db:build-patches (item existing / pts area is-hole verts n i p0 p1 p2 patch patches corners dupes failed)
  (setq pts (cadr item))
  (setq area (caddr item))
  (setq is-hole (cadddr item))
  (setq verts (db:item-verts item))
  (setq n (length pts))
  (setq i 0)
  (setq patches '())
  (setq corners 0)
  (setq dupes 0)
  (setq failed 0)
  (if (and is-hole (not *db-process-holes*))
    (list '() 0 0 0)
    (progn
      (while (< i n)
        (setq p0 (nth (rem (+ i n -1) n) pts))
        (setq p1 (nth i pts))
        (setq p2 (nth (rem (1+ i) n) pts))
        (if (db:auto-corner-candidate-p verts i p0 p1 p2 area is-hole)
          (progn
            (setq corners (1+ corners))
            (setq patch (db:create-patch p0 p1 p2 i))
            (setq patch (db:attach-source-bulges patch verts i))
            (if patch
              (if (db:duplicate-patch-p patch (append existing patches) *db-duplicate-tol*)
                (setq dupes (1+ dupes))
                (setq patches (cons patch patches))
              )
              (setq failed (1+ failed))
            )
          )
        )
        (setq i (1+ i))
      )
      (list (reverse patches) corners dupes failed)
    )
  )
)

(defun db:build-replacement-vertices (item patches / verts n i patch next-patch vertices)
  (setq verts (db:item-verts item))
  (setq n (length verts))
  (setq i 0)
  (setq vertices '())
  (while (< i n)
    (setq patch (db:find-patch i patches))
    (setq next-patch (db:find-patch (rem (1+ i) n) patches))
    (if patch
      (progn
        (setq vertices
          (append
            vertices
            (list
              (list (cdr (assoc 'start patch)) (cdr (assoc 'bulge patch)))
              (list (cdr (assoc 'end patch)) (db:patch-after-bulge patch))
            )
          )
        )
      )
      (setq vertices
        (append
          vertices
          (list
            (list
              (car (nth i verts))
              (if next-patch (db:patch-before-bulge next-patch) (cadr (nth i verts)))
            )
          )
        )
      )
    )
    (setq i (1+ i))
  )
  vertices
)

(defun db:rebuild-polyline-from-vertices (item vertices / layer color ltype lweight owner)
  (setq layer (nth 4 item))
  (if (not layer) (setq layer "0"))
  (setq color (nth 5 item))
  (setq ltype (nth 6 item))
  (setq lweight (nth 7 item))
  (setq owner (cdr (assoc 330 (entget (car item)))))
  (if (>= (length vertices) 3)
    (db:make-lwpolyline-owned owner layer color ltype lweight vertices)
    nil
  )
)

(defun db:rebuild-polyline (item patches)
  (db:rebuild-polyline-from-vertices item (db:build-replacement-vertices item patches))
)

(defun db:lwpoly-vertex-code-p (code)
  (or (= code 10) (= code 40) (= code 41) (= code 42) (= code 91))
)

(defun db:lwpoly-trailing-code-p (code)
  (= code 210)
)

;;; Modify an existing LWPOLYLINE without changing its handle or owner. This is
;;; required for block-definition entities: creating a replacement with entmakex
;;; can place the result in model space instead of the original block definition.
(defun db:update-lwpolyline-in-place (ename vertices / ed header trailing d modified v)
  (setq ed (entget ename))
  (setq header '())
  (setq trailing '())
  (foreach d ed
    (cond
      ((= (car d) 90)
        (setq header (append header (list (cons 90 (length vertices)))))
      )
      ((db:lwpoly-vertex-code-p (car d)))
      ((db:lwpoly-trailing-code-p (car d))
        (setq trailing (append trailing (list d)))
      )
      (T (setq header (append header (list d))))
    )
  )
  (setq modified header)
  (foreach v vertices
    (setq modified
      (append
        modified
        (list
          (cons 10 (db:pt2d (car v)))
          (cons 42 (cadr v))
        )
      )
    )
  )
  (setq modified (append modified trailing))
  (entmod modified)
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

(defun db:process-dbauto-group (group-kind items / tagged item result patch patches all-patches
                                      poly-count hole-count corner-count dogbone-count
                                      duplicate-count failed-count rebuilt-count circle-data
                                      circle-detected-count circle-converted-count
                                      circle-failed-count vertices newent)
  (setq tagged (db:tag-holes items))
  (setq poly-count (length tagged))
  (setq hole-count 0)
  (setq corner-count 0)
  (setq dogbone-count 0)
  (setq duplicate-count 0)
  (setq failed-count 0)
  (setq rebuilt-count 0)
  (setq circle-detected-count 0)
  (setq circle-converted-count 0)
  (setq circle-failed-count 0)
  (setq all-patches '())
  (foreach item tagged
    (setq newent nil)
    (setq circle-data (db:item-circle-data item))
    (if (cadddr item) (setq hole-count (1+ hole-count)))
    (if circle-data
      (progn
        (setq circle-detected-count (1+ circle-detected-count))
        (if (= group-kind 'block)
          (setq newent
            (db:update-lwpolyline-in-place
              (car item)
              (db:circle-polyline-vertices (car circle-data) (cadr circle-data) (caddr item))
            )
          )
          (progn
            (setq newent (db:make-circle-from-item item circle-data))
            (if (and newent (not *db-keep-original*)) (entdel (car item)))
          )
        )
        (if newent
          (setq circle-converted-count (1+ circle-converted-count))
          (setq circle-failed-count (1+ circle-failed-count))
        )
      )
      (progn
        (setq result (db:build-patches item all-patches))
        (setq patches (car result))
        (setq all-patches (append all-patches patches))
        (setq corner-count (+ corner-count (cadr result)))
        (setq dogbone-count (+ dogbone-count (length patches)))
        (setq duplicate-count (+ duplicate-count (caddr result)))
        (setq failed-count (+ failed-count (cadddr result)))
        (if *db-debug-mode*
          (foreach patch patches (db:draw-debug-patch patch))
        )
        (if patches
          (progn
            (setq vertices (db:build-replacement-vertices item patches))
            (if (= group-kind 'block)
              (setq newent (db:update-lwpolyline-in-place (car item) vertices))
              (progn
                (setq newent (db:rebuild-polyline-from-vertices item vertices))
                (if (and newent (not *db-keep-original*)) (entdel (car item)))
              )
            )
            (if newent
              (setq rebuilt-count (1+ rebuilt-count))
            )
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
    (cons 'failed failed-count)
    (cons 'rebuilt rebuilt-count)
    (cons 'circles-detected circle-detected-count)
    (cons 'circles-converted circle-converted-count)
    (cons 'circle-failures circle-failed-count)
  )
)

(defun c:DBAUTO (/ olderr ss selection groups group stats skipped-open skipped-bulge
                   direct-count block-count skipped-blocks poly-count hole-count
                   corner-count dogbone-count duplicate-count failed-count rebuilt-count
                   circle-detected-count circle-converted-count circle-failed-count)
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
      (setq failed-count 0)
      (setq rebuilt-count 0)
      (setq circle-detected-count 0)
      (setq circle-converted-count 0)
      (setq circle-failed-count 0)
      (foreach group groups
        (setq stats (db:process-dbauto-group (car group) (nth 2 group)))
        (setq poly-count (+ poly-count (cdr (assoc 'valid stats))))
        (setq hole-count (+ hole-count (cdr (assoc 'holes stats))))
        (setq corner-count (+ corner-count (cdr (assoc 'corners stats))))
        (setq dogbone-count (+ dogbone-count (cdr (assoc 'dogbones stats))))
        (setq duplicate-count (+ duplicate-count (cdr (assoc 'duplicates stats))))
        (setq failed-count (+ failed-count (cdr (assoc 'failed stats))))
        (setq rebuilt-count (+ rebuilt-count (cdr (assoc 'rebuilt stats))))
        (setq circle-detected-count (+ circle-detected-count (cdr (assoc 'circles-detected stats))))
        (setq circle-converted-count (+ circle-converted-count (cdr (assoc 'circles-converted stats))))
        (setq circle-failed-count (+ circle-failed-count (cdr (assoc 'circle-failures stats))))
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
          ", dogbone geometry failed="
          (itoa failed-count)
          ", rebuilt polylines="
          (itoa rebuilt-count)
          ", segmented circles detected="
          (itoa circle-detected-count)
          ", circles converted="
          (itoa circle-converted-count)
          ", circle conversions failed="
          (itoa circle-failed-count)
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
;;; Arranges selected LWPOLYLINE / INSERT parts across copied rectangular sheets
;;; using an AABB MaxRects packing algorithm.
;;; Commands: DBNSET (set gap/margin), DBNEST (multi sheet), DBNESTM (compatibility alias).
;;; =========================================================================

;;; ---------------------------------------------------------------------------
;;; db:lwpoly-bbox  —  AABB for a LWPOLYLINE entity
;;; Returns (min-x min-y max-x max-y) or nil
;;; ---------------------------------------------------------------------------
(defun db:positive-angle (a)
  (while (< a 0.0)
    (setq a (+ a (* 2.0 pi)))
  )
  (while (>= a (* 2.0 pi))
    (setq a (- a (* 2.0 pi)))
  )
  a
)

(defun db:ccw-angle-delta (from-angle to-angle)
  (db:positive-angle (- to-angle from-angle))
)

(defun db:angle-on-bulge-arc-p (angle start-angle end-angle bulge / span offset)
  (if (> bulge 0.0)
    (progn
      (setq span (* 4.0 (atan bulge)))
      (setq offset (db:ccw-angle-delta start-angle angle))
      (<= offset (+ span *db-eps*))
    )
    (progn
      (setq span (* -4.0 (atan bulge)))
      (setq offset (db:ccw-angle-delta angle start-angle))
      (<= offset (+ span *db-eps*))
    )
  )
)

(defun db:bulge-arc-bbox-points (start end bulge
                                 / chord len mid unit left center-dist center radius
                                   start-angle end-angle angles a pts)
  (setq pts '())
  (if (> (abs bulge) *db-eps*)
    (progn
      (setq chord (db:sub end start))
      (setq len (db:len chord))
      (if (> len *db-eps*)
        (progn
          (setq mid (db:mul (db:add start end) 0.5))
          (setq unit (db:mul chord (/ 1.0 len)))
          (setq left (list (- (db:y unit)) (db:x unit) 0.0))
          (setq center-dist (/ (* len (- 1.0 (* bulge bulge))) (* 4.0 bulge)))
          (setq center (db:add mid (db:mul left center-dist)))
          (setq radius (/ (* len (+ 1.0 (* bulge bulge))) (* 4.0 (abs bulge))))
          (setq start-angle (db:angle (db:sub start center)))
          (setq end-angle (db:angle (db:sub end center)))
          (setq angles (list 0.0 (/ pi 2.0) pi (* 1.5 pi)))
          (foreach a angles
            (if (db:angle-on-bulge-arc-p a start-angle end-angle bulge)
              (setq pts (cons (db:point-on-circle center radius a) pts))
            )
          )
        )
      )
    )
  )
  pts
)

(defun db:lwpoly-bbox-points (closed verts / pts n i current next)
  (setq pts (db:vertex-points verts))
  (setq n (length verts))
  (setq i 0)
  (while (< i n)
    (if (or closed (< i (1- n)))
      (progn
        (setq current (nth i verts))
        (setq next (nth (rem (1+ i) n) verts))
        (setq pts
          (append
            pts
            (db:bulge-arc-bbox-points (car current) (car next) (cadr current))
          )
        )
      )
    )
    (setq i (1+ i))
  )
  pts
)

(defun db:bbox-from-points (pts / p minx miny maxx maxy)
  (if (or (not pts) (null pts))
    nil
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

(defun db:lwpoly-bbox (ename / data closed verts pts)
  (setq data (db:lwpoly-data ename))
  (setq closed (car data))
  (setq verts (cadr data))
  (if (null verts)
    nil
    (progn
      (setq pts (db:lwpoly-bbox-points closed verts))
      (db:bbox-from-points pts)
    )
  )
)

(defun db:circle-bbox (ename / ed center radius)
  (setq ed (entget ename))
  (setq center (cdr (assoc 10 ed)))
  (setq radius (cdr (assoc 40 ed)))
  (if (and center radius)
    (list
      (- (db:x center) radius)
      (- (db:y center) radius)
      (+ (db:x center) radius)
      (+ (db:y center) radius)
    )
    nil
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
                                data pts v px py rx ry cos-r sin-r
                                circle-center circle-radius
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
            (setq pts (db:lwpoly-bbox-points (car data) (cadr data)))
            (foreach v pts
              (setq px (* (db:x v) sx))
              (setq py (* (db:y v) sy))
              ;; rotate
              (setq rx (- (* px cos-r) (* py sin-r)))
              (setq ry (+ (* px sin-r) (* py cos-r)))
              ;; translate
              (setq allpts (cons (list (+ rx insx) (+ ry insy) 0.0) allpts))
            )
          )
          ((= etype "CIRCLE")
            (setq circle-center (cdr (assoc 10 ed)))
            (setq circle-radius (cdr (assoc 40 ed)))
            (if (and circle-center circle-radius)
              (progn
                (setq pts
                  (list
                    (list (+ (db:x circle-center) circle-radius) (db:y circle-center) 0.0)
                    (list (- (db:x circle-center) circle-radius) (db:y circle-center) 0.0)
                    (list (db:x circle-center) (+ (db:y circle-center) circle-radius) 0.0)
                    (list (db:x circle-center) (- (db:y circle-center) circle-radius) 0.0)
                  )
                )
                (foreach v pts
                  (setq px (* (db:x v) sx))
                  (setq py (* (db:y v) sy))
                  (setq rx (- (* px cos-r) (* py sin-r)))
                  (setq ry (+ (* px sin-r) (* py cos-r)))
                  (setq allpts (cons (list (+ rx insx) (+ ry insy) 0.0) allpts))
                )
              )
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

(defun db:bbox-inset (bbox inset / w h)
  (setq inset (max 0.0 inset))
  (setq w (db:bbox-width bbox))
  (setq h (db:bbox-height bbox))
  (if (and (> w (* 2.0 inset))
           (> h (* 2.0 inset)))
    (list
      (+ (nth 0 bbox) inset)
      (+ (nth 1 bbox) inset)
      (- (nth 2 bbox) inset)
      (- (nth 3 bbox) inset)
    )
    bbox
  )
)

(defun db:sheet-placement-bbox (sheet-bbox gap)
  (db:bbox-inset sheet-bbox gap)
)

(defun db:normalize-sheet-gap (sheet-gap)
  (if (and sheet-gap (> sheet-gap 0.0))
    sheet-gap
    50.0
  )
)

(defun db:entity-in-parts-p (ename parts / found part en)
  (setq found nil)
  (foreach part parts
    (foreach en (car part)
      (if (eq ename en)
        (setq found T)
      )
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
      (setq result (cons (list (car board) occupied (nth 2 board)) result))
      (setq result (cons board result))
    )
    (setq i (1+ i))
  )
  (reverse result)
)

(defun db:update-board-state (boards index occupied free-rects / result i board)
  (setq result '())
  (setq i 0)
  (foreach board boards
    (if (= i index)
      (setq result (cons (list (car board) occupied free-rects) result))
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
    ((= etype "CIRCLE")     (db:circle-bbox ename))
    (T nil)
  )
)

;;; ---------------------------------------------------------------------------
;;; db:collect-nest-parts  —  Prompt user to select parts and compute AABBs
;;; Returns list of ((ename ...) bbox width height area entity-type)
;;; ---------------------------------------------------------------------------
(defun db:bbox-contains-bbox-p (outer inner /)
  (and
    (<= (nth 0 outer) (+ (nth 0 inner) *db-eps*))
    (<= (nth 1 outer) (+ (nth 1 inner) *db-eps*))
    (>= (nth 2 outer) (- (nth 2 inner) *db-eps*))
    (>= (nth 3 outer) (- (nth 3 inner) *db-eps*))
  )
)

(defun db:bbox-union (a b /)
  (list
    (min (nth 0 a) (nth 0 b))
    (min (nth 1 a) (nth 1 b))
    (max (nth 2 a) (nth 2 b))
    (max (nth 3 a) (nth 3 b))
  )
)

(defun db:nest-item-parent (item items / parent parent-area item-en item-bbox item-area other other-en other-bbox other-area)
  (setq parent nil)
  (setq parent-area nil)
  (setq item-en (car item))
  (setq item-bbox (cadr item))
  (setq item-area (caddr item))
  (foreach other items
    (setq other-en (car other))
    (setq other-bbox (cadr other))
    (setq other-area (caddr other))
    (if (and
          (not (eq item-en other-en))
          (> other-area (+ item-area *db-eps*))
          (db:bbox-contains-bbox-p other-bbox item-bbox)
          (or (not parent-area) (< other-area parent-area)))
      (progn
        (setq parent other-en)
        (setq parent-area other-area)
      )
    )
  )
  parent
)

(defun db:group-nest-items (items / parts item parent root-en root-bbox entities bbox child child-parent w h a)
  (setq parts '())
  (foreach item items
    (setq parent (db:nest-item-parent item items))
    (if (not parent)
      (progn
        (setq root-en (car item))
        (setq root-bbox (cadr item))
        (setq entities (list root-en))
        (setq bbox root-bbox)
        (foreach child items
          (setq child-parent (db:nest-item-parent child items))
          (if (eq child-parent root-en)
            (progn
              (setq entities (append entities (list (car child))))
              (setq bbox (db:bbox-union bbox (cadr child)))
            )
          )
        )
        (setq w (db:bbox-width bbox))
        (setq h (db:bbox-height bbox))
        (setq a (db:bbox-area bbox))
        (setq parts (cons (list entities bbox w h a "GROUP") parts))
      )
    )
  )
  (reverse parts)
)

(defun db:collect-nest-parts (/ ss i n en bbox a etype items parts)
  (prompt "\n选择要排料的零件 (LWPOLYLINE、INSERT 或 CIRCLE): ")
  (setq ss (ssget '((0 . "LWPOLYLINE,INSERT,CIRCLE"))))
  (if (not ss)
    nil
    (progn
      (setq items '())
      (setq i 0)
      (setq n (sslength ss))
      (setq *db-last-nest-raw-count* n)
      (while (< i n)
        (setq en (ssname ss i))
        (setq bbox (db:entity-aabb en))
        (if bbox
          (progn
            (setq a (db:bbox-area bbox))
            (setq etype (cdr (assoc 0 (entget en))))
            (setq items (cons (list en bbox a etype) items))
          )
          (prompt (strcat "\n警告: 第 " (itoa (1+ i)) " 个实体无法计算 AABB，已跳过。"))
        )
        (setq i (1+ i))
      )
      (setq parts (db:group-nest-items (reverse items)))
      (setq *db-last-nest-group-count* (length parts))
      parts
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
  (setq ss (ssget "_C" minpt maxpt '((0 . "LWPOLYLINE,INSERT,CIRCLE"))))
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
(defun db:part-sort-value (part mode / w h)
  (setq w (nth 2 part))
  (setq h (nth 3 part))
  (cond
    ((= mode "WIDTH") w)
    ((= mode "HEIGHT") h)
    ((= mode "LONG") (max w h))
    (T (nth 4 part))
  )
)

(defun db:sort-by-mode-desc (parts mode / sorted rest item inserted tmp result)
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
      (if (>= (db:part-sort-value (car tmp) mode) (db:part-sort-value item mode))
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

(defun db:sort-by-area-desc (parts)
  (db:sort-by-mode-desc parts "AREA")
)

(defun db:nest-sort-variants (parts)
  (list
    (list "AREA" (db:sort-by-mode-desc parts "AREA"))
    (list "WIDTH" (db:sort-by-mode-desc parts "WIDTH"))
    (list "HEIGHT" (db:sort-by-mode-desc parts "HEIGHT"))
    (list "LONG" (db:sort-by-mode-desc parts "LONG"))
  )
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

(defun db:bbox-list-union (bboxes / union b)
  (setq union nil)
  (foreach b bboxes
    (if b
      (if union
        (setq union (db:bbox-union union b))
        (setq union b)
      )
    )
  )
  union
)

(defun db:score-better-p (score best-score / better decided i a b)
  (if (not best-score)
    T
    (progn
      (setq better nil)
      (setq decided nil)
      (setq i 0)
      (while (and (not decided) (< i (length score)))
        (setq a (nth i score))
        (setq b (nth i best-score))
        (if (< a (- b *db-eps*))
          (progn
            (setq better T)
            (setq decided T)
          )
          (if (> a (+ b *db-eps*))
            (progn
              (setq better nil)
              (setq decided T)
            )
          )
        )
        (setq i (1+ i))
      )
      better
    )
  )
)

(defun db:placement-score (candidate occupied sheet-bbox / union used-w used-h)
  (setq union (db:bbox-list-union (cons candidate occupied)))
  (setq used-w (- (nth 2 union) (nth 0 sheet-bbox)))
  (setq used-h (- (nth 3 union) (nth 1 sheet-bbox)))
  (list
    (* used-w used-h)
    used-h
    used-w
    (- (nth 1 candidate) (nth 1 sheet-bbox))
    (- (nth 0 candidate) (nth 0 sheet-bbox))
  )
)

(defun db:find-placement (part sheet-bbox gap occupied
                          / orientations orient angle pw ph xs ys x y candidate score best-score placement)
  (setq placement nil)
  (setq best-score nil)
  (setq orientations (db:part-orientations part))
  (setq xs (db:candidate-xs sheet-bbox occupied gap))
  (setq ys (db:candidate-ys sheet-bbox occupied gap))
  (foreach y ys
    (foreach x xs
      (foreach orient orientations
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
          (progn
            (setq score (db:placement-score candidate occupied sheet-bbox))
            (if (db:score-better-p score best-score)
              (progn
                (setq best-score score)
                (setq placement (list x y angle candidate))
              )
            )
          )
        )
        )
      )
    )
  )
  placement
)

(defun db:maxrect-bbox-valid-p (bbox)
  (and
    bbox
    (> (db:bbox-width bbox) *db-eps*)
    (> (db:bbox-height bbox) *db-eps*)
  )
)

(defun db:maxrect-inflate-bbox (bbox gap /)
  (list
    (- (nth 0 bbox) gap)
    (- (nth 1 bbox) gap)
    (+ (nth 2 bbox) gap)
    (+ (nth 3 bbox) gap)
  )
)

(defun db:maxrect-split-free-rect (free blocker / pieces r)
  (setq pieces '())
  (if (not (db:bbox-overlaps free blocker))
    (list free)
    (progn
      (setq r (list (nth 0 free) (nth 1 free) (nth 0 blocker) (nth 3 free)))
      (if (db:maxrect-bbox-valid-p r) (setq pieces (cons r pieces)))
      (setq r (list (nth 2 blocker) (nth 1 free) (nth 2 free) (nth 3 free)))
      (if (db:maxrect-bbox-valid-p r) (setq pieces (cons r pieces)))
      (setq r (list (nth 0 free) (nth 1 free) (nth 2 free) (nth 1 blocker)))
      (if (db:maxrect-bbox-valid-p r) (setq pieces (cons r pieces)))
      (setq r (list (nth 0 free) (nth 3 blocker) (nth 2 free) (nth 3 free)))
      (if (db:maxrect-bbox-valid-p r) (setq pieces (cons r pieces)))
      pieces
    )
  )
)

(defun db:maxrect-contained-p (inner outer /)
  (and
    (<= (nth 0 outer) (+ (nth 0 inner) *db-eps*))
    (<= (nth 1 outer) (+ (nth 1 inner) *db-eps*))
    (>= (nth 2 outer) (- (nth 2 inner) *db-eps*))
    (>= (nth 3 outer) (- (nth 3 inner) *db-eps*))
  )
)

(defun db:maxrect-prune-free-rects (free-rects / pruned rect other contained)
  (setq pruned '())
  (foreach rect free-rects
    (if (db:maxrect-bbox-valid-p rect)
      (progn
        (setq contained nil)
        (foreach other free-rects
          (if (and
                (not (equal rect other))
                (db:maxrect-bbox-valid-p other)
                (db:maxrect-contained-p rect other))
            (setq contained T)
          )
        )
        (if (not contained)
          (setq pruned (cons rect pruned))
        )
      )
    )
  )
  (reverse pruned)
)

(defun db:maxrect-subtract-blocker (free-rects blocker / result rect pieces)
  (setq result '())
  (foreach rect free-rects
    (setq pieces (db:maxrect-split-free-rect rect blocker))
    (foreach piece pieces
      (setq result (cons piece result))
    )
  )
  (db:maxrect-prune-free-rects result)
)

(defun db:maxrect-update-free-rects (free-rects candidate gap / blocker)
  (setq blocker (db:maxrect-inflate-bbox candidate gap))
  (db:maxrect-subtract-blocker free-rects blocker)
)

(defun db:maxrect-init-free-rects (sheet-placement-bbox obstacles gap / free-rects obstacle)
  (setq free-rects (list sheet-placement-bbox))
  (foreach obstacle obstacles
    (setq free-rects
      (db:maxrect-subtract-blocker free-rects (db:maxrect-inflate-bbox obstacle gap))
    )
  )
  free-rects
)

(defun db:maxrect-anchors ()
  (list "LB" "RB" "LT" "RT")
)

(defun db:maxrect-anchor-candidate (free width height anchor / x y)
  (setq x
    (if (or (= anchor "RB") (= anchor "RT"))
      (- (nth 2 free) width)
      (nth 0 free)
    )
  )
  (setq y
    (if (or (= anchor "LT") (= anchor "RT"))
      (- (nth 3 free) height)
      (nth 1 free)
    )
  )
  (db:bbox-make x y width height)
)

(defun db:maxrect-largest-free-area (free-rects / largest rect area)
  (setq largest 0.0)
  (foreach rect free-rects
    (setq area (db:bbox-area rect))
    (if (> area largest)
      (setq largest area)
    )
  )
  largest
)

(defun db:maxrect-placement-score (candidate free updated-free-rects / leftover-w leftover-h short-side long-side)
  (setq leftover-w (- (db:bbox-width free) (db:bbox-width candidate)))
  (setq leftover-h (- (db:bbox-height free) (db:bbox-height candidate)))
  (setq short-side (min leftover-w leftover-h))
  (setq long-side (max leftover-w leftover-h))
  (list
    (- (db:bbox-area free) (db:bbox-area candidate))
    short-side
    long-side
    (length updated-free-rects)
    (- 0.0 (db:maxrect-largest-free-area updated-free-rects))
    (nth 1 candidate)
    (nth 0 candidate)
  )
)

(defun db:maxrect-find-placement (part free-rects gap
                                  / orientations anchors anchor orient free angle pw ph candidate updated-free-rects score best-score placement)
  (setq placement nil)
  (setq best-score nil)
  (setq orientations (db:part-orientations part))
  (setq anchors (db:maxrect-anchors))
  (foreach free free-rects
    (foreach anchor anchors
      (foreach orient orientations
        (setq angle (car orient))
        (setq pw (cadr orient))
        (setq ph (caddr orient))
        (if (and
              (<= pw (+ (db:bbox-width free) *db-eps*))
              (<= ph (+ (db:bbox-height free) *db-eps*)))
          (progn
            (setq candidate (db:maxrect-anchor-candidate free pw ph anchor))
            (setq updated-free-rects (db:maxrect-update-free-rects free-rects candidate gap))
            (setq score (db:maxrect-placement-score candidate free updated-free-rects))
            (if (db:score-better-p score best-score)
              (progn
                (setq best-score score)
                (setq placement
                  (list
                    (nth 0 candidate)
                    (nth 1 candidate)
                    angle
                    candidate
                    updated-free-rects
                  )
                )
              )
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
  (setq sheet-gap (db:normalize-sheet-gap sheet-gap))
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

(defun db:multi-sheet-pack (parts template-bbox gap edge-margin sheet-gap initial-obstacles
                            / boards results part placed board-index board placement
                              occupied candidate free-rects new-index new-bbox new-sheet
                              new-free-rects occupied-sheet-bboxes)
  (setq sheet-gap (db:normalize-sheet-gap sheet-gap))
  (setq boards
    (list
      (list
        template-bbox
        initial-obstacles
        (db:maxrect-init-free-rects (db:sheet-placement-bbox template-bbox edge-margin) initial-obstacles gap)
      )
    )
  )
  (setq occupied-sheet-bboxes (list template-bbox))
  (setq results '())
  (foreach part parts
    (setq placed nil)
    (setq board-index 0)
    (foreach board boards
      (if (not placed)
        (progn
          (setq placement (db:maxrect-find-placement part (nth 2 board) gap))
          (if placement
            (progn
              (setq placed T)
              (setq occupied (cadr board))
              (setq candidate (cadddr placement))
              (setq free-rects (nth 4 placement))
              (setq boards (db:update-board-state boards board-index (cons candidate occupied) free-rects))
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
        (setq placement
          (db:maxrect-find-placement part (db:maxrect-init-free-rects (db:sheet-placement-bbox new-bbox edge-margin) '() gap) gap)
        )
        (if placement
          (progn
            (setq candidate (cadddr placement))
            (setq new-free-rects (nth 4 placement))
            (setq occupied-sheet-bboxes (append occupied-sheet-bboxes (list new-bbox)))
            (setq boards (append boards (list (list new-bbox (list candidate) new-free-rects))))
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

(defun db:result-board-index (result)
  (nth 4 result)
)

(defun db:tail-board-index (results / tail r idx)
  (setq tail 0)
  (foreach r results
    (if (nth 5 r)
      (progn
        (setq idx (db:result-board-index r))
        (if (> idx tail)
          (setq tail idx)
        )
      )
    )
  )
  tail
)

(defun db:tail-board-results (results / tail tail-results r)
  (setq tail (db:tail-board-index results))
  (setq tail-results '())
  (foreach r results
    (if (and (nth 5 r) (= (db:result-board-index r) tail))
      (setq tail-results (cons r tail-results))
    )
  )
  (reverse tail-results)
)

(defun db:non-tail-board-results (results / tail kept r)
  (setq tail (db:tail-board-index results))
  (setq kept '())
  (foreach r results
    (if (not (and (nth 5 r) (= (db:result-board-index r) tail)))
      (setq kept (cons r kept))
    )
  )
  (reverse kept)
)

(defun db:drop-last-board (boards / kept remaining)
  (setq kept '())
  (setq remaining boards)
  (while (cdr remaining)
    (setq kept (cons (car remaining) kept))
    (setq remaining (cdr remaining))
  )
  (reverse kept)
)

(defun db:result-part (result / entities bbox)
  (setq entities (car result))
  (setq bbox (db:entities-aabb entities))
  (if bbox
    (list
      entities
      bbox
      (db:bbox-width bbox)
      (db:bbox-height bbox)
      (db:bbox-area bbox)
      "GROUP"
    )
    nil
  )
)

(defun db:try-place-result-on-earlier-board (result boards tail-index gap
                                             / part board-index board placement occupied candidate free-rects)
  (setq part (db:result-part result))
  (setq board-index 0)
  (setq placement nil)
  (while (and part (not placement) (< board-index tail-index) (< board-index (length boards)))
    (setq board (nth board-index boards))
    (setq placement (db:maxrect-find-placement part (nth 2 board) gap))
    (if placement
      (progn
        (setq occupied (cadr board))
        (setq candidate (cadddr placement))
        (setq free-rects (nth 4 placement))
        (setq boards (db:update-board-state boards board-index (cons candidate occupied) free-rects))
      )
      (setq board-index (1+ board-index))
    )
  )
  (if placement
    (list
      T
      boards
      (list
        (car result)
        (car placement)
        (cadr placement)
        (caddr placement)
        board-index
        T
      )
    )
    (list nil boards result)
  )
)

(defun db:compact-tail-board (packed gap / results boards tail-index tail-results kept-results moved-results
                                     working-boards ok attempt r)
  (setq results (car packed))
  (setq boards (cadr packed))
  (setq *db-last-tail-compact-before* (length boards))
  (setq *db-last-tail-compact-after* (length boards))
  (setq *db-last-tail-compact-count* 0)
  (setq *db-last-tail-compact-status* "SKIPPED")
  (setq tail-index (db:tail-board-index results))
  (if (or (<= (length boards) 1)
          (<= tail-index 0)
          (/= tail-index (1- (length boards))))
    packed
    (progn
      (setq tail-results (db:tail-board-results results))
      (setq kept-results (db:non-tail-board-results results))
      (setq moved-results '())
      (setq working-boards boards)
      (setq ok T)
      (foreach r tail-results
        (if ok
          (progn
            (setq attempt (db:try-place-result-on-earlier-board r working-boards tail-index gap))
            (if (car attempt)
              (progn
                (setq working-boards (cadr attempt))
                (setq moved-results (cons (caddr attempt) moved-results))
              )
              (setq ok nil)
            )
          )
        )
      )
      (if ok
        (progn
          (setq *db-last-tail-compact-status* "REMOVED")
          (setq *db-last-tail-compact-count* (length tail-results))
          (setq *db-last-tail-compact-after* (length (db:drop-last-board working-boards)))
          (list
            (append kept-results (reverse moved-results))
            (db:drop-last-board working-boards)
          )
        )
        (progn
          (setq *db-last-tail-compact-status* "FAILED")
          (setq *db-last-tail-compact-count* (length tail-results))
          packed
        )
      )
    )
  )
)

(defun db:pack-score (packed / results boards unplaced used-area used-w used-h board union score-board r)
  (setq results (car packed))
  (setq boards (cadr packed))
  (setq unplaced 0)
  (foreach r results
    (if (not (nth 5 r))
      (setq unplaced (1+ unplaced))
    )
  )
  (setq used-area 0.0)
  (setq used-w 0.0)
  (setq used-h 0.0)
  (foreach board boards
    (setq union (db:bbox-list-union (cadr board)))
    (if union
      (progn
        (setq score-board (car board))
        (setq used-area (+ used-area (db:bbox-area union)))
        (setq used-w (+ used-w (- (nth 2 union) (nth 0 score-board))))
        (setq used-h (+ used-h (- (nth 3 union) (nth 1 score-board))))
      )
    )
  )
  (list unplaced (length boards) used-area used-h used-w)
)

(defun db:multi-sheet-pack-best (parts template-bbox gap edge-margin sheet-gap initial-obstacles
                                 / variants variant label sorted packed compacted score best best-score best-label
                                   best-compact-status best-compact-before best-compact-after best-compact-count)
  (setq variants (db:nest-sort-variants parts))
  (setq best nil)
  (setq best-score nil)
  (setq best-label "AREA")
  (setq best-compact-status "SKIPPED")
  (setq best-compact-before 0)
  (setq best-compact-after 0)
  (setq best-compact-count 0)
  (foreach variant variants
    (setq label (car variant))
    (setq sorted (cadr variant))
    (setq packed (db:multi-sheet-pack sorted template-bbox gap edge-margin sheet-gap initial-obstacles))
    (setq compacted (db:compact-tail-board packed gap))
    (setq *db-last-tail-compact-after* (length (cadr compacted)))
    (setq score (db:pack-score compacted))
    (if (db:score-better-p score best-score)
      (progn
        (setq best compacted)
        (setq best-score score)
        (setq best-label label)
        (setq best-compact-status *db-last-tail-compact-status*)
        (setq best-compact-before *db-last-tail-compact-before*)
        (setq best-compact-after *db-last-tail-compact-after*)
        (setq best-compact-count *db-last-tail-compact-count*)
      )
    )
  )
  (setq *db-last-tail-compact-status* best-compact-status)
  (setq *db-last-tail-compact-before* best-compact-before)
  (setq *db-last-tail-compact-after* best-compact-after)
  (setq *db-last-tail-compact-count* best-compact-count)
  (list (car best) (cadr best) best-label best-score)
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
  (command "_.MOVE" ename "" "_non" from-pt "_non" to-pt)
)

(defun db:rotate-entity-90 (ename bbox / base)
  (setq base (list (nth 0 bbox) (nth 1 bbox) 0.0))
  (command "_.ROTATE" ename "" "_non" base "90")
)

(defun db:copy-sheet-frame (sheet-en source-bbox target-bbox / from-pt to-pt copied)
  (setq from-pt (list (nth 0 source-bbox) (nth 1 source-bbox) 0.0))
  (setq to-pt (list (nth 0 target-bbox) (nth 1 target-bbox) 0.0))
  (command "_.COPY" sheet-en "" "_non" from-pt "_non" to-pt)
  (setq copied (entlast))
  copied
)

(defun db:entities-aabb (entities / bbox en ebbox)
  (setq bbox nil)
  (foreach en entities
    (setq ebbox (db:entity-aabb en))
    (if ebbox
      (if bbox
        (setq bbox (db:bbox-union bbox ebbox))
        (setq bbox ebbox)
      )
    )
  )
  bbox
)

(defun db:rotate-entities-90 (entities bbox / base en)
  (setq base (list (nth 0 bbox) (nth 1 bbox) 0.0))
  (foreach en entities
    (command "_.ROTATE" en "" "_non" base "90")
  )
)

(defun db:place-nested-part (entities tx ty angle / bbox from-pt to-pt en)
  (setq bbox (db:entities-aabb entities))
  (if bbox
    (progn
      (if (= angle 90)
        (progn
          (db:rotate-entities-90 entities bbox)
          (setq bbox (db:entities-aabb entities))
        )
      )
      (setq from-pt (list (nth 0 bbox) (nth 1 bbox) 0.0))
      (setq to-pt (list tx ty 0.0))
      (foreach en entities
        (db:move-entity-to en from-pt to-pt)
      )
    )
  )
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
(defun c:DBNSET (/ g m)
  (prompt (strcat "\n当前组件间距: " (rtos *db-nest-gap* 2 2) " mm"))
  (prompt (strcat "\n当前边缘留边: " (rtos *db-nest-edge-margin* 2 2) " mm"))
  (setq g (getreal (strcat "\n输入新的排料间距 <" (rtos *db-nest-gap* 2 2) ">: ")))
  (if (and g (>= g 0.0))
    (setq *db-nest-gap* g)
  )
  (setq m (getreal (strcat "\n输入新的边缘留边 <" (rtos *db-nest-edge-margin* 2 2) ">: ")))
  (if (and m (>= m 0.0))
    (setq *db-nest-edge-margin* m)
  )
  (prompt (strcat "\n组件间距已设为: " (rtos *db-nest-gap* 2 2) " mm"))
  (prompt (strcat "\n边缘留边已设为: " (rtos *db-nest-edge-margin* 2 2) " mm"))
  (princ)
)

;;; ---------------------------------------------------------------------------
;;; db:run-multi-sheet-nest  —  Shared multi-sheet nesting command runner
;;; ---------------------------------------------------------------------------
(defun db:run-multi-sheet-nest (command-name
                                / olderr parts sheet sheet-en sheet-bbox obstacles
                                  sheet-gap packed results boards board-count strategy
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
          (setq *db-nest-sheet-gap* (db:normalize-sheet-gap *db-nest-sheet-gap*))
          (setq gap-input
            (getreal
              (strcat
                "\n输入复制板框之间的水平间距 <"
                (rtos *db-nest-sheet-gap* 2 2)
                ">: "
              )
            )
          )
          (if (and gap-input (> gap-input 0.0))
            (setq *db-nest-sheet-gap* gap-input)
          )
          (setq sheet-gap *db-nest-sheet-gap*)
          (setq obstacles (db:collect-sheet-obstacles sheet-en sheet-bbox parts))
          (prompt
            (strcat
              "\nDBNEST-DIAG version=" *db-version*
              ", raw-selected=" (itoa *db-last-nest-raw-count*)
              ", grouped-parts=" (itoa *db-last-nest-group-count*)
              ", sheet-gap=" (rtos sheet-gap 2 2)
              ", nest-gap=" (rtos *db-nest-gap* 2 2)
              ", edge-margin=" (rtos *db-nest-edge-margin* 2 2)
            )
          )
          (prompt
            (strcat
              "\n开始多板排料... 零件数: " (itoa (length parts))
              ", 首板已占用: " (itoa (length obstacles))
              ", 零件间距: " (rtos *db-nest-gap* 2 2)
              ", 边缘留边: " (rtos *db-nest-edge-margin* 2 2)
              ", 板框间距: " (rtos sheet-gap 2 2)
            )
          )
          (setq packed (db:multi-sheet-pack-best parts sheet-bbox *db-nest-gap* *db-nest-edge-margin* sheet-gap obstacles))
          (setq results (car packed))
          (setq boards (cadr packed))
          (setq strategy (caddr packed))
          (prompt (strcat "\nDBNEST-DIAG strategy=" strategy))
          (prompt
            (strcat
              "\nDBNEST-DIAG tail-compact=" *db-last-tail-compact-status*
              ", compact-before=" (itoa *db-last-tail-compact-before*)
              ", compact-after=" (itoa *db-last-tail-compact-after*)
              ", compact-tail-parts=" (itoa *db-last-tail-compact-count*)
            )
          )
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
                (db:place-nested-part en tx ty angle)
                (setq placed-count (1+ placed-count))
              )
              (setq remain-count (1+ remain-count))
            )
          )
          (prompt
            (strcat
              "\n" command-name " 完成。共 " (itoa total-count)
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

;;; ---------------------------------------------------------------------------
;;; c:DBNEST  —  Main nesting command
;;; ---------------------------------------------------------------------------
(defun c:DBNEST ()
  (db:run-multi-sheet-nest "DBNEST")
)

;;; ---------------------------------------------------------------------------
;;; c:DBNESTM  —  Multi-sheet nesting command
;;; ---------------------------------------------------------------------------
(defun c:DBNESTM ()
  (db:run-multi-sheet-nest "DBNESTM")
)

(prompt (strcat "\nDogbone plugin " *db-version* " loaded. Commands: DBVER, DBSET, DB1, DBDEBUG, DBAUTO, DBADD, DBRESTORE, DBRESTOREALL, DBNSET, DBNEST, DBNESTM."))
(princ)
