classdef ReaderConsole < handle
    %READERCONSOLE Human-in-the-loop review of AI screening results in < 30 s.
    %
    %   app = netra.ui.ReaderConsole('results/queue')     folder of exportCase files
    %   app = netra.ui.ReaderConsole(folder, 'Reader', 'Dr. Rao', 'Log', 'review_log.csv')
    %   netra.ui.ReaderConsole.demo()                     builds a queue from phantoms
    %
    %   The queue is ordered as a reading room would work it: URGENT, REFER,
    %   HUMAN_REVIEW, then the audit sample of ROUTINE cases, each by
    %   descending P(referable). For every eye the reader sees the annotated
    %   image, the grade distribution with its conformal set, the criteria
    %   that fired and why the AI decided what it did - and decides with one
    %   key:
    %
    %     Enter / Space   agree with the AI
    %     0 1 2 3 4       override the ICDR grade
    %     U               ungradable - recapture
    %     R E L A         view: raw, enhanced, lesions, attention
    %     Z X C V B       rate the explanation 1..5 (optional)
    %     N / P           next / previous without deciding
    %
    %   A stopwatch runs from the moment a case is shown; it turns amber at
    %   20 s and red at 30 s. Every decision is appended to a CSV audit log
    %   (reader, case, AI grade and triage, reader grade and triage,
    %   agreement, seconds, views used, explanation rating). summary()
    %   reports median review time, the share under 30 s, agreement and the
    %   quadratic weighted kappa between reader and AI - the evidence that
    %   the explanations make review both fast and safe.
    %
    %   Requires MATLAB R2021a or later (uifigure).

    properties
        Cases = {}
        Files = {}
        Index = 0
        Reader = 'reader'
        LogFile = ''
        Mode = 'lesions'
        Log
    end
    properties (Access = private)
        Fig
        Queue
        Ax
        Img
        TriageLbl
        FollowLbl
        MsgLbl
        ProbAx
        CritLbl
        ReasonLbl
        ClockLbl
        StatsLbl
        ModeBtns
        Rating = NaN
        ViewsUsed = {}
        T0
        Tick
        Pal
    end

    methods
        function app = ReaderConsole(source, varargin)
            if netra.util.isOctave() || ~netra.util.has('uifigure')
                error('netra:ui:matlab', 'The Reader Console needs MATLAB R2021a+ (uifigure).');
            end
            o = netra.util.opts(struct('Reader', 'reader', 'Log', ''), varargin{:});
            app.Reader = o.Reader;
            app.Pal = netra.util.palette();
            app.loadQueue(source);
            if isempty(o.Log)
                o.Log = fullfile(pwd, 'netrasetu_review_log.csv');
            end
            app.LogFile = o.Log;
            app.Log = struct('time', {}, 'reader', {}, 'caseId', {}, 'aiTriage', {}, ...
                'aiGrade', {}, 'aiPReferable', {}, 'readerTriage', {}, 'readerGrade', {}, ...
                'agree', {}, 'seconds', {}, 'views', {}, 'rating', {});
            app.build();
            if ~isempty(app.Cases)
                app.show(1);
            end
        end

        function delete(app)
            if ~isempty(app.Tick) && isvalid(app.Tick)
                stop(app.Tick);
                delete(app.Tick);
            end
            if ~isempty(app.Fig) && isvalid(app.Fig)
                delete(app.Fig);
            end
        end

        function S = summary(app)
            %SUMMARY Review-time and agreement statistics of this session.
            L = app.Log;
            S = struct('cases', numel(L), 'medianSeconds', NaN, 'under30', NaN, ...
                'agreement', NaN, 'qwk', NaN, 'meanRating', NaN);
            if isempty(L)
                return
            end
            t = [L.seconds];
            S.medianSeconds = median(t);
            S.under30 = mean(t <= 30);
            S.agreement = mean([L.agree]);
            ai = [L.aiGrade];
            rd = [L.readerGrade];
            ok = isfinite(ai) & isfinite(rd);
            if nnz(ok) >= 2
                S.qwk = netra.eval.qwk(ai(ok), rd(ok), 5);
            end
            r = [L.rating];
            if any(isfinite(r))
                S.meanRating = mean(r(isfinite(r)));
            end
        end
    end

    methods (Static)
        function app = demo(n)
            %DEMO Screen n phantoms (default 8) and open them in the console.
            if nargin < 1, n = 8; end
            cfg = netra.config();
            folder = fullfile(tempdir, 'netrasetu_demo_queue');
            grades = mod(0:n - 1, 5);
            fprintf('Screening %d phantom eyes for the demo queue...\n', n);
            for k = 1:n
                [rgb, ~] = netra.phantom.generate('Grade', grades(k), 'Seed', 900 + k, 'Size', 768);
                R = netra.screen(rgb, 'Config', cfg, 'ID', sprintf('DEMO-%03d', k), ...
                    'Site', 'Phantom queue');
                netra.ui.exportCase(R, folder);
            end
            app = netra.ui.ReaderConsole(folder, 'Reader', 'demo');
        end
    end

    methods (Access = private)
        function loadQueue(app, source)
            if iscell(source)
                app.Cases = source;
            else
                d = dir(fullfile(source, '*.mat'));
                app.Files = fullfile({d.folder}, {d.name});
                app.Cases = cell(1, numel(d));
                for k = 1:numel(d)
                    S = load(app.Files{k}, 'C');
                    app.Cases{k} = S.C;
                end
            end
            order = {'URGENT', 'REFER', 'HUMAN_REVIEW', 'RECAPTURE', 'ROUTINE'};
            key = zeros(1, numel(app.Cases));
            for k = 1:numel(app.Cases)
                c = app.Cases{k};
                pr = c.decision.pReferable;
                if ~isfinite(pr), pr = 0; end
                key(k) = 10 * find(strcmp(order, c.decision.triage), 1) - pr;
            end
            [~, idx] = sort(key);
            app.Cases = app.Cases(idx);
        end

        function build(app)
            P = app.Pal;
            app.Fig = uifigure('Name', 'NetraSetu - Reader Console', 'Position', [60 60 1480 880], ...
                'Color', P.paper);
            app.Fig.KeyPressFcn = @(~, evt) app.onKey(evt);
            app.Fig.CloseRequestFcn = @(~, ~) delete(app);
            g = uigridlayout(app.Fig, [3 3]);
            g.RowHeight = {64, '1x', 44};
            g.ColumnWidth = {250, '1x', 440};
            g.Padding = [12 12 12 12];
            g.RowSpacing = 10;
            g.ColumnSpacing = 12;
            g.BackgroundColor = P.paper;

            head = uilabel(g, 'Text', '  NetraSetu  |  Reader Console', 'FontSize', 22, ...
                'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', P.ink);
            head.Layout.Row = 1; head.Layout.Column = [1 2];
            app.ClockLbl = uilabel(g, 'Text', '0.0 s', 'FontSize', 30, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', 'FontColor', [1 1 1], 'BackgroundColor', P.ink);
            app.ClockLbl.Layout.Row = 1; app.ClockLbl.Layout.Column = 3;

            % queue
            app.Queue = uitable(g, 'ColumnName', {'Case', 'AI triage', 'P(ref)'}, ...
                'RowName', {}, 'ColumnWidth', {90, 90, 50}, 'FontSize', 12);
            app.Queue.Layout.Row = 2; app.Queue.Layout.Column = 1;
            app.Queue.CellSelectionCallback = @(~, evt) app.onSelect(evt);
            app.refreshQueue();

            % image + view buttons
            mid = uigridlayout(g, [2 1]);
            mid.RowHeight = {'1x', 36};
            mid.Padding = [0 0 0 0];
            mid.BackgroundColor = P.paper;
            mid.Layout.Row = 2; mid.Layout.Column = 2;
            app.Ax = uiaxes(mid);
            app.Ax.Layout.Row = 1;
            app.Ax.XTick = []; app.Ax.YTick = [];
            app.Ax.XColor = 'none'; app.Ax.YColor = 'none';
            app.Ax.Color = P.paper;
            app.Ax.Toolbar.Visible = 'off';
            disableDefaultInteractivity(app.Ax);
            bar = uigridlayout(mid, [1 4]);
            bar.Padding = [0 0 0 0];
            bar.BackgroundColor = P.paper;
            bar.Layout.Row = 2;
            modes = {'raw', 'enhanced', 'lesions', 'attention'};
            keys = {'R', 'E', 'L', 'A'};
            app.ModeBtns = gobjects(1, 4);
            for k = 1:4
                app.ModeBtns(k) = uibutton(bar, 'Text', sprintf('%s  [%s]', modes{k}, keys{k}), ...
                    'ButtonPushedFcn', @(~, ~) app.setMode(modes{k}));
            end

            % decision panel
            right = uigridlayout(g, [8 1]);
            right.RowHeight = {56, 26, 50, 150, '1x', 80, 44, 34};
            right.Padding = [0 0 0 0];
            right.RowSpacing = 6;
            right.BackgroundColor = P.paper;
            right.Layout.Row = 2; right.Layout.Column = 3;
            app.TriageLbl = uilabel(right, 'Text', '', 'FontSize', 26, 'FontWeight', 'bold', ...
                'FontColor', [1 1 1], 'HorizontalAlignment', 'center');
            app.FollowLbl = uilabel(right, 'Text', '', 'FontSize', 13, 'FontColor', P.ink);
            app.MsgLbl = uilabel(right, 'Text', '', 'FontSize', 13, 'WordWrap', 'on', ...
                'FontColor', P.inkSoft);
            app.ProbAx = uiaxes(right);
            app.ProbAx.Toolbar.Visible = 'off';
            disableDefaultInteractivity(app.ProbAx);
            app.CritLbl = uilabel(right, 'Text', '', 'FontSize', 12.5, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top', 'Interpreter', 'html');
            app.ReasonLbl = uilabel(right, 'Text', '', 'FontSize', 12, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top', 'FontColor', P.inkSoft);

            act = uigridlayout(right, [1 7]);
            act.Padding = [0 0 0 0];
            act.ColumnSpacing = 4;
            act.BackgroundColor = P.paper;
            act.ColumnWidth = {'2x', '1x', '1x', '1x', '1x', '1x', '1.3x'};
            uibutton(act, 'Text', 'Agree  [Enter]', 'FontWeight', 'bold', 'FontColor', [1 1 1], ...
                'BackgroundColor', P.ROUTINE, 'ButtonPushedFcn', @(~, ~) app.decide('agree', NaN));
            for gr = 0:4
                uibutton(act, 'Text', sprintf('%d', gr), 'FontWeight', 'bold', ...
                    'BackgroundColor', P.grades(gr + 1, :), 'FontColor', [1 1 1], ...
                    'ButtonPushedFcn', @(~, ~) app.decide('grade', gr));
            end
            uibutton(act, 'Text', 'Ungradable [U]', 'BackgroundColor', P.RECAPTURE, ...
                'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) app.decide('ungradable', NaN));

            rate = uigridlayout(right, [1 6]);
            rate.Padding = [0 0 0 0];
            rate.BackgroundColor = P.paper;
            rate.ColumnWidth = {'2.2x', '1x', '1x', '1x', '1x', '1x'};
            uilabel(rate, 'Text', 'Explanation useful?', 'FontColor', P.inkSoft);
            rk = {'Z', 'X', 'C', 'V', 'B'};
            for k = 1:5
                uibutton(rate, 'Text', sprintf('%d [%s]', k, rk{k}), ...
                    'ButtonPushedFcn', @(~, ~) app.rate(k));
            end

            app.StatsLbl = uilabel(g, 'Text', '', 'FontSize', 13, 'FontColor', P.ink);
            app.StatsLbl.Layout.Row = 3; app.StatsLbl.Layout.Column = [1 3];
            app.Tick = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.2, ...
                'TimerFcn', @(~, ~) app.tickClock(), 'BusyMode', 'drop');
        end

        function refreshQueue(app)
            n = numel(app.Cases);
            data = cell(n, 3);
            for k = 1:n
                c = app.Cases{k};
                data{k, 1} = c.id;
                data{k, 2} = strrep(c.decision.triage, '_', ' ');
                data{k, 3} = sprintf('%.2f', c.decision.pReferable);
            end
            app.Queue.Data = data;
        end

        function show(app, k)
            if k < 1 || k > numel(app.Cases)
                return
            end
            app.Index = k;
            app.Rating = NaN;
            app.ViewsUsed = {};
            c = app.Cases{k};
            P = app.Pal;
            app.TriageLbl.Text = strrep(c.decision.triage, '_', ' ');
            app.TriageLbl.BackgroundColor = c.decision.colour;
            app.FollowLbl.Text = sprintf('%s   |   %s', c.id, c.decision.followUp);
            app.MsgLbl.Text = sprintf('%s\n%s', c.decision.message.en, c.decision.message.hi);
            app.drawProbabilities(c);
            app.CritLbl.Text = criteriaHTML(c, P);
            app.ReasonLbl.Text = ['Why: ' strjoin(c.decision.reasons, '; ')];
            app.setMode(app.Mode);
            app.ViewsUsed = {app.Mode};
            app.startClock();
            app.updateStats();
        end

        function drawProbabilities(app, c)
            ax = app.ProbAx;
            cla(ax);
            P = app.Pal;
            p = c.P;
            if any(~isfinite(p))
                title(ax, 'No grade (image not gradable)');
                return
            end
            hold(ax, 'on');
            for k = 1:5
                bar(ax, k - 1, p(k), 0.6, 'FaceColor', P.grades(k, :), 'EdgeColor', 'none');
                text(ax, k - 1, p(k) + 0.06, sprintf('%.0f%%', 100 * p(k)), ...
                    'HorizontalAlignment', 'center', 'FontSize', 10);
            end
            cs = c.conformalSet;
            if ~isempty(cs) && any(cs)
                f = find(cs, 1, 'first') - 1;
                l = find(cs, 1, 'last') - 1;
                plot(ax, [f - 0.35 l + 0.35], [1.12 1.12], 'k-', 'LineWidth', 1.5);
                text(ax, (f + l) / 2, 1.2, 'conformal set', 'HorizontalAlignment', 'center', ...
                    'FontSize', 9);
            end
            hold(ax, 'off');
            ax.XLim = [-0.6 4.6];
            ax.YLim = [0 1.3];
            ax.XTick = 0:4;
            ax.XTickLabel = {'0 none', '1 mild', '2 mod', '3 sev', '4 PDR'};
            ax.YTick = [];
            ax.Box = 'off';
            ax.Color = P.paper;
            title(ax, sprintf('ICDR grade %d   |   P(referable) %.2f', c.grade, c.decision.pReferable), ...
                'FontSize', 12);
        end

        function setMode(app, mode)
            app.Mode = mode;
            if app.Index < 1
                return
            end
            c = app.Cases{app.Index};
            img = c.images.(mode);
            cla(app.Ax);
            image(app.Ax, img);
            axis(app.Ax, 'image');
            app.Ax.XTick = []; app.Ax.YTick = [];
            if strcmp(mode, 'attention') && ~isempty(c.attentionKind)
                title(app.Ax, ['Attention: ' c.attentionKind], 'FontSize', 12);
            else
                title(app.Ax, '');
            end
            names = {'raw', 'enhanced', 'lesions', 'attention'};
            for k = 1:4
                if strcmp(names{k}, mode)
                    app.ModeBtns(k).BackgroundColor = app.Pal.saffron;
                else
                    app.ModeBtns(k).BackgroundColor = [0.96 0.96 0.96];
                end
            end
            if ~any(strcmp(app.ViewsUsed, mode))
                app.ViewsUsed{end + 1} = mode;
            end
        end

        function onKey(app, evt)
            k = lower(evt.Key);
            switch k
                case {'return', 'space'}
                    app.decide('agree', NaN);
                case {'0', '1', '2', '3', '4', 'numpad0', 'numpad1', 'numpad2', 'numpad3', 'numpad4'}
                    app.decide('grade', str2double(k(end)));
                case 'u'
                    app.decide('ungradable', NaN);
                case 'r', app.setMode('raw');
                case 'e', app.setMode('enhanced');
                case 'l', app.setMode('lesions');
                case 'a', app.setMode('attention');
                case {'z', 'x', 'c', 'v', 'b'}
                    app.rate(find(strcmp({'z', 'x', 'c', 'v', 'b'}, k)));
                case {'n', 'rightarrow'}
                    app.show(min(app.Index + 1, numel(app.Cases)));
                case {'p', 'leftarrow'}
                    app.show(max(app.Index - 1, 1));
            end
        end

        function onSelect(app, evt)
            if ~isempty(evt.Indices)
                app.show(evt.Indices(1, 1));
            end
        end

        function rate(app, k)
            app.Rating = k;
            app.StatsLbl.Text = sprintf('Explanation rated %d / 5 for this case.', k);
        end

        function decide(app, action, grade)
            if app.Index < 1
                return
            end
            secs = toc(app.T0);
            app.stopClock();
            c = app.Cases{app.Index};
            aiGrade = c.grade;
            switch action
                case 'agree'
                    rGrade = aiGrade;
                    rTriage = c.decision.triage;
                case 'grade'
                    rGrade = grade;
                    if grade >= 4
                        rTriage = 'URGENT';
                    elseif grade >= 2 || c.dme >= 2
                        rTriage = 'REFER';
                    else
                        rTriage = 'ROUTINE';
                    end
                otherwise
                    rGrade = NaN;
                    rTriage = 'RECAPTURE';
            end
            e = struct('time', datestr(now, 'yyyy-mm-dd HH:MM:SS'), 'reader', app.Reader, ...
                'caseId', c.id, 'aiTriage', c.decision.triage, 'aiGrade', aiGrade, ...
                'aiPReferable', c.decision.pReferable, 'readerTriage', rTriage, ...
                'readerGrade', rGrade, 'agree', strcmp(rTriage, c.decision.triage) && ...
                (isequaln(rGrade, aiGrade)), 'seconds', secs, ...
                'views', strjoin(app.ViewsUsed, '+'), 'rating', app.Rating);
            app.Log(end + 1) = e;
            app.appendLog(e);
            app.Queue.Data{app.Index, 2} = sprintf('%s -> %s', strrep(c.decision.triage, '_', ' '), rTriage);
            if app.Index < numel(app.Cases)
                app.show(app.Index + 1);
            else
                app.updateStats();
                uialert(app.Fig, statsText(app.summary()), 'Queue complete', 'Icon', 'success');
            end
        end

        function appendLog(app, e)
            T = struct2table(e, 'AsArray', true);
            if exist(app.LogFile, 'file')
                writetable(T, app.LogFile, 'WriteMode', 'append');
            else
                writetable(T, app.LogFile);
            end
        end

        function updateStats(app)
            app.StatsLbl.Text = sprintf('Case %d of %d   |   %s   |   log: %s', app.Index, ...
                numel(app.Cases), statsText(app.summary()), app.LogFile);
        end

        function startClock(app)
            app.T0 = tic;
            if strcmp(app.Tick.Running, 'off')
                start(app.Tick);
            end
        end

        function stopClock(app)
            if ~isempty(app.Tick) && isvalid(app.Tick)
                stop(app.Tick);
            end
        end

        function tickClock(app)
            if isempty(app.Fig) || ~isvalid(app.Fig)
                return
            end
            s = toc(app.T0);
            app.ClockLbl.Text = sprintf('%.1f s', s);
            if s >= 30
                app.ClockLbl.BackgroundColor = app.Pal.URGENT;
            elseif s >= 20
                app.ClockLbl.BackgroundColor = app.Pal.REFER;
            else
                app.ClockLbl.BackgroundColor = app.Pal.ink;
            end
        end
    end
end

function h = criteriaHTML(c, P)
hex = @(col) sprintf('#%02X%02X%02X', round(255 * col));
rows = '';
for k = 1:numel(c.criteria)
    q = c.criteria(k);
    if q.met
        col = hex(P.grades(min(q.level + 1, 5), :));
        rows = [rows sprintf('<div><span style="color:%s">&#9679;</span> <b>%s</b></div>', col, q.text)]; %#ok<AGROW>
    end
end
if isempty(rows)
    rows = '<div style="color:#6B7280">No ICDR criterion met.</div>';
end
if c.dme >= 1
    rows = [rows sprintf('<div><span style="color:%s">&#9679;</span> <b>Macular oedema risk %d</b></div>', ...
        hex(P.REFER), c.dme)];
end
h = rows;
end

function s = statsText(S)
if S.cases == 0
    s = 'no decisions yet';
    return
end
s = sprintf('%d reviewed  |  median %.1f s  |  %.0f %% under 30 s  |  agreement %.0f %%  |  QWK %.2f', ...
    S.cases, S.medianSeconds, 100 * S.under30, 100 * S.agreement, S.qwk);
end
