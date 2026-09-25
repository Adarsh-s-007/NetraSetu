function file = diagramSVG(file)
%DIAGRAMSVG Draw the Simulink model's structure as SVG, from its description.
%
%   netra.sim.diagramSVG('docs/img/simulink_model.svg')
%
%   Same source as netra.sim.buildSimulink (netra.sim.simulinkBlocks), so
%   the picture cannot drift from the model: seven stage blocks with their
%   ports, the workspace inputs that drive them (top), every signal between
%   stages (adjacent stages directly, the rest on a bus underneath) and the
%   signals logged to the workspace. For documentation where Simulink is not
%   installed; the .slx itself is built with netra.sim.buildSimulink.
M = netra.sim.simulinkBlocks();
P = netra.util.palette();
hex = @(c) sprintf('#%02X%02X%02X', round(255 * c));
nb = numel(M.blocks);
W = 208;                                    % card width
G = 64;                                     % gap between cards
x0 = 30;
top = 150;
rowH = 19;
nPort = max(arrayfun(@(b) max(numel(b.in), numel(b.out)), M.blocks));
H = 58 + rowH * nPort;
x = x0 + (0:nb - 1) * (W + G);
width = x(end) + W + 40;
stripe = {'#2a78d6', '#2a78d6', '#eb6834', '#E8930C', '#1baf7a', '#1baf7a', '#3D4DB7'};
src = containers.Map({M.sources.name}, {M.sources.kind});
prod = containers.Map();
for b = 1:nb
    for j = 1:numel(M.blocks(b).out)
        prod(M.blocks(b).out{j}) = [b j];
    end
end
inY = @(b, j) top + 50 + (j - 0.5) * rowH;
outY = @(b, j) top + 50 + (j - 0.5) * rowH;

s = {};
% wires first (under the cards); bus lanes for non-adjacent links
lane = 0;
busTop = top + H + 34;
for b = 1:nb
    B = M.blocks(b);
    for j = 1:numel(B.in)
        n = B.in{j};
        if ~prod.isKey(n)
            continue
        end
        p = prod(n);
        xa = x(p(1)) + W;
        ya = outY(p(1), p(2));
        xb = x(b);
        yb = inY(b, j);
        if p(1) == b - 1
            xm = xa + 0.3 * G + 4 * (mod(j, 3) - 1);
            s{end + 1} = sprintf(['<path d="M%.1f %.1f H%.1f V%.1f H%.1f" class="w"/>' ...
                '<circle cx="%.1f" cy="%.1f" r="2.2" class="d"/>'], xa, ya, xm, yb, xb - 6, xb - 6, yb); %#ok<AGROW>
        else
            lane = lane + 1;
            yl = busTop + 15 * lane;
            xo = xa + 10 + 4 * lane;
            xi = xb - 14 - 4 * lane;
            xt = (xo + xi) / 2 + 30 * (mod(lane, 2) - 0.5);
            tw = 6.2 * numel(n) + 8;
            s{end + 1} = sprintf(['<path d="M%.1f %.1f H%.1f V%.1f H%.1f V%.1f H%.1f" class="w bus"/>' ...
                '<circle cx="%.1f" cy="%.1f" r="2.2" class="d"/>' ...
                '<rect x="%.1f" y="%.1f" width="%.1f" height="12" class="bg"/>' ...
                '<text x="%.1f" y="%.1f" class="bl">%s</text>'], xa, ya, xo, yl, xi, yb, xb - 6, ...
                xb - 6, yb, xt - tw / 2, yl - 6, tw, xt, yl + 3.5, n); %#ok<AGROW>
        end
    end
end
% workspace inputs above the cards
for b = 1:nb
    B = M.blocks(b);
    k = 0;
    for j = 1:numel(B.in)
        n = B.in{j};
        if src.isKey(n) && strcmp(src(n), 'series')
            k = k + 1;
            cx = x(b) + 14 + (k - 1) * 66;
            cy = 62 + 26 * mod(k - 1, 2);
            s{end + 1} = sprintf(['<rect x="%.1f" y="%.1f" width="62" height="20" rx="10" class="in"/>' ...
                '<text x="%.1f" y="%.1f" class="it">%s</text>' ...
                '<path d="M%.1f %.1f V%.1f" class="w in"/>'], cx, cy, cx + 31, cy + 14, label(n), ...
                cx + 31, cy + 20, top - 4); %#ok<AGROW>
        end
    end
end
% cards
logged = {M.logs.signal};
for b = 1:nb
    B = M.blocks(b);
    s{end + 1} = sprintf(['<rect x="%.1f" y="%d" width="%d" height="%d" rx="10" class="card"/>' ...
        '<rect x="%.1f" y="%d" width="6" height="%d" rx="3" fill="%s"/>' ...
        '<text x="%.1f" y="%d" class="h">%s</text>' ...
        '<text x="%.1f" y="%d" class="sub">%s</text>'], x(b), top, W, H, x(b), top, H, ...
        stripe{min(b, numel(stripe))}, x(b) + 16, top + 24, esc(B.name), x(b) + 16, top + 40, ...
        esc(regexprep(B.label, '^\d+\s+', ''))); %#ok<AGROW>
    for j = 1:numel(B.in)
        n = B.in{j};
        cls = 'p';
        if src.isKey(n) && strcmp(src(n), 'constant')
            cls = 'p c';
        end
        s{end + 1} = sprintf('<text x="%.1f" y="%.1f" class="%s">%s</text>', x(b) + 12, ...
            inY(b, j) + 4, cls, n); %#ok<AGROW>
    end
    for j = 1:numel(B.out)
        n = B.out{j};
        mark = '';
        if any(strcmp(logged, n))
            mark = sprintf('<circle cx="%.1f" cy="%.1f" r="3.2" class="log"/>', x(b) + W + 1, outY(b, j));
        end
        s{end + 1} = sprintf('<text x="%.1f" y="%.1f" class="p o">%s</text>%s', x(b) + W - 12, ...
            outY(b, j) + 4, n, mark); %#ok<AGROW>
    end
end
hTot = busTop + 15 * (lane + 1) + 58;
legendY = hTot - 26;
head = sprintf(['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" ' ...
    'font-family="Noto Sans, Segoe UI, Helvetica, Arial, sans-serif">' ...
    '<style>.card{fill:#fff;stroke:%s;stroke-width:1.2}.h{font-size:15px;font-weight:700;fill:%s}' ...
    '.sub{font-size:11px;fill:%s}.p{font-size:11.5px;fill:%s;font-family:Menlo,Consolas,monospace}' ...
    '.p.c{fill:%s}.p.o{text-anchor:end}.w{fill:none;stroke:%s;stroke-width:1.3}.w.bus{stroke:%s;' ...
    'stroke-dasharray:4 3}.w.in{stroke:%s}.d{fill:%s}.bl{font-size:10px;fill:%s;font-family:Menlo,Consolas,monospace;' ...
    'text-anchor:middle}.bg{fill:%s}' ...
    '.in{fill:%s;stroke:none}.it{font-size:10.5px;fill:#fff;text-anchor:middle;font-weight:600}' ...
    '.log{fill:%s}.t{font-size:18px;font-weight:800;fill:%s}.n{font-size:12px;fill:%s}</style>' ...
    '<rect width="100%%" height="100%%" fill="%s"/>' ...
    '<text x="%d" y="30" class="t">%s</text>' ...
    '<text x="%d" y="48" class="n">MATLAB Function blocks (queues as persistent state), From Workspace ' ...
    'inputs from nsim, To Workspace logs. Built by netra.sim.buildSimulink; the same block code runs in ' ...
    'CI through netra.sim.emulateBlocks.</text>'], width, hTot, width, hTot, hex(P.rule), hex(P.ink), ...
    hex(P.inkSoft), hex(P.ink), hex(P.inkSoft * 0.6 + 0.4), hex(P.inkSoft), hex(P.inkSoft), ...
    '#898781', hex(P.ink), hex(P.inkSoft), hex(P.paper), '#52514e', hex(P.saffron), hex(P.ink), hex(P.inkSoft), ...
    hex(P.paper), x0, esc(M.title), x0);
foot = sprintf(['<g transform="translate(%d %d)"><rect width="46" height="16" rx="8" class="in"/>' ...
    '<text x="23" y="12" class="it">input</text><text x="56" y="12" class="n">time series from ' ...
    'netra.sim.prepare (arrivals, capacities, link outages, rosters)</text>' ...
    '<circle cx="520" cy="8" r="3.2" class="log"/><text x="530" y="12" class="n">logged to the ' ...
    'workspace</text><text x="690" y="12" class="p c">grey</text><text x="724" y="12" class="n">' ...
    'constant (parameters p, initial queues)</text><path d="M960 8 H1000" class="w bus"/>' ...
    '<text x="1008" y="12" class="n">signal to a later stage</text></g></svg>'], x0, legendY);
fid = fopen(file, 'w');
fprintf(fid, '%s', head, s{:}, foot);
fclose(fid);
end

function t = label(n)
names = struct('arrivals', 'arrivals', 'capCapture', 'cameras', 'closing', 'closing', ...
    'upCap', 'link', 'graderCap', 'graders', 'ophthCap', 'ophthal.');
t = n;
if isfield(names, n)
    t = names.(n);
end
end

function s = esc(s)
s = strrep(strrep(strrep(s, '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
end
