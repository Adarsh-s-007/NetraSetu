classdef ScreeningApp < handle
    %SCREENINGAPP Open a fundus photograph, screen it, read the result, save the report.
    %
    %   app = netra.ui.ScreeningApp()                 open a photograph or a practice eye
    %   app = netra.ui.ScreeningApp('eye.jpg')        screen that photograph straight away
    %   app = netra.ui.ScreeningApp(..., 'Models', M, 'Config', cfg, 'Site', 'PHC Nanded')
    %
    %   The desktop twin of the web demo's "Check an eye". Open photo reads
    %   any file netra.io.readFundus reads and netra.screen runs the whole
    %   pipeline on it: quality gate, anatomy, lesions, the graders that are
    %   trained, explanation and triage. The window shows
    %     left    the annotated fundus (Show marks off: the photograph as
    %             standardised), or the photograph when it must be retaken
    %     right   the triage banner and follow-up, the patient message in
    %             English and Hindi, what was found, the grade distribution
    %             with P(referable), the ICDR criteria with their measured
    %             values, the reasons for the triage, and image quality with
    %             the operator's feedback
    %   Save report writes the bilingual HTML report (netra.xai.reportHTML)
    %   and, next to it, the A4 figure as PNG (netra.xai.reportFigure). Send
    %   to reader exports the case for netra.ui.ReaderConsole.
    %
    %   Keys: O open, P practice eye, M marks on/off, S save report.
    %   Scripted use: app.screenImage(rgb, id), app.Result, app.saveReport(file).
    %   Requires MATLAB R2021a or later (uifigure).

    properties
        Result = []
        Config
        Models
        Site = ''
    end
    properties (Access = private)
        Fig
        Ax
        MarksBox
        PracticeDrop
        SaveBtn
        QueueBtn
        TriageLbl
        FollowLbl
        MsgLbl
        FoundLbl
        ProbAx
        CritLbl
        WhyLbl
        QualityLbl
        StatusLbl
        Pal
    end

    methods
        function app = ScreeningApp(file, varargin)
            if netra.util.isOctave() || ~netra.util.has('uifigure')
                error('netra:ui:matlab', 'The Screening App needs MATLAB R2021a+ (uifigure).');
            end
            if nargin < 1
                file = '';
            end
            o = netra.util.opts(struct('Config', [], 'Models', [], 'Site', ''), varargin{:});
            app.Config = o.Config;
            if isempty(app.Config)
                app.Config = netra.config();
            end
            app.Models = o.Models;
            if isempty(app.Models)
                app.Models = netra.loadModels(app.Config);
            end
            app.Site = o.Site;
            app.Pal = netra.util.palette();
            app.build();
            app.showEmpty();
            if ~isempty(file)
                app.openFile(file);
            end
        end

        function delete(app)
            if ~isempty(app.Fig) && isvalid(app.Fig)
                delete(app.Fig);
            end
        end

        function screenImage(app, rgb, id, file)
            %SCREENIMAGE Screen an RGB image and show the result.
            if nargin < 3 || isempty(id)
                id = ['EYE-' datestr(now, 'yyyymmdd-HHMMSS')];
            end
            if nargin < 4
                file = '';
            end
            d = uiprogressdlg(app.Fig, 'Title', 'NetraSetu', 'Indeterminate', 'on', ...
                'Message', 'Checking the photograph: quality, landmarks, lesions, grade...');
            try
                R = netra.screen(rgb, 'Models', app.Models, 'Config', app.Config, ...
                    'ID', id, 'Site', app.Site);
            catch err
                closeDialog(d);
                uialert(app.Fig, err.message, 'Screening failed');
                return
            end
            closeDialog(d);
            R.meta.file = file;
            app.Result = R;
            app.show();
        end

        function openFile(app, file)
            %OPENFILE Read a photograph from disk and screen it.
            try
                rgb = netra.io.readFundus(file);
            catch err
                uialert(app.Fig, err.message, 'Cannot open the photograph');
                return
            end
            [~, id] = fileparts(file);
            app.screenImage(rgb, id, file);
        end

        function files = saveReport(app, file)
            %SAVEREPORT Write the HTML report and the A4 PNG; returns both paths.
            files = {};
            R = app.Result;
            if isempty(R) || ~isfield(R, 'fusion')
                return
            end
            if nargin < 2 || isempty(file)
                base = regexprep(R.meta.id, '[^\w\-]', '_');
                [f, p] = uiputfile({'*.html', 'Bilingual HTML report (*.html)'}, ...
                    'Save the screening report', [base '_report.html']);
                figure(app.Fig);
                if isequal(f, 0)
                    return
                end
                file = fullfile(p, f);
            end
            netra.xai.reportHTML(R, file);
            [p, n] = fileparts(file);
            png = fullfile(p, [n '.png']);
            fig = netra.xai.reportFigure(R, 'File', png);
            close(fig);
            files = {file, png};
            app.StatusLbl.Text = sprintf('  Saved %s and %s', file, png);
        end
    end

    methods (Access = private)
        function build(app)
            P = app.Pal;
            app.Fig = uifigure('Name', 'NetraSetu - Check an eye', 'Position', [60 60 1360 860], ...
                'Color', P.paper);
            app.Fig.KeyPressFcn = @(~, evt) app.onKey(evt);
            app.Fig.CloseRequestFcn = @(~, ~) delete(app);
            g = uigridlayout(app.Fig, [3 2]);
            g.RowHeight = {56, '1x', 26};
            g.ColumnWidth = {'1x', 460};
            g.Padding = [12 12 12 8];
            g.RowSpacing = 10;
            g.ColumnSpacing = 14;
            g.BackgroundColor = P.paper;

            % ---------------------------------------------------- toolbar
            bar = uigridlayout(g, [1 7]);
            bar.Layout.Row = 1; bar.Layout.Column = [1 2];
            bar.ColumnWidth = {250, 150, 170, 190, '1x', 150, 150};
            bar.Padding = [12 8 12 8];
            bar.ColumnSpacing = 10;
            bar.BackgroundColor = P.ink;
            uilabel(bar, 'Text', 'NetraSetu  |  Check an eye', 'FontSize', 20, ...
                'FontWeight', 'bold', 'FontColor', [1 1 1]);
            uibutton(bar, 'Text', 'Open photo...  [O]', 'FontWeight', 'bold', ...
                'BackgroundColor', P.saffron, 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~, ~) app.openDialog());
            app.PracticeDrop = uidropdown(bar, 'Items', {'Practice eye: grade 0', ...
                'Practice eye: grade 1', 'Practice eye: grade 2', 'Practice eye: grade 3', ...
                'Practice eye: grade 4'}, 'ItemsData', 0:4, 'Value', 2);
            uibutton(bar, 'Text', 'Check practice eye  [P]', ...
                'ButtonPushedFcn', @(~, ~) app.practice());
            uilabel(bar, 'Text', '');
            app.SaveBtn = uibutton(bar, 'Text', 'Save report  [S]', ...
                'ButtonPushedFcn', @(~, ~) app.saveReport());
            app.QueueBtn = uibutton(bar, 'Text', 'Send to reader', ...
                'ButtonPushedFcn', @(~, ~) app.toQueue());

            % ------------------------------------------------------ image
            left = uigridlayout(g, [2 1]);
            left.Layout.Row = 2; left.Layout.Column = 1;
            left.RowHeight = {'1x', 30};
            left.Padding = [0 0 0 0];
            left.BackgroundColor = P.paper;
            app.Ax = uiaxes(left);
            app.Ax.XTick = []; app.Ax.YTick = [];
            app.Ax.XColor = 'none'; app.Ax.YColor = 'none';
            app.Ax.Color = P.paper;
            app.Ax.Toolbar.Visible = 'off';
            disableDefaultInteractivity(app.Ax);
            app.MarksBox = uicheckbox(left, 'Text', 'Show marks  [M]', 'Value', true, ...
                'FontSize', 13, 'ValueChangedFcn', @(~, ~) app.drawImage());

            % ----------------------------------------------------- result
            right = uigridlayout(g, [8 1]);
            right.Layout.Row = 2; right.Layout.Column = 2;
            right.RowHeight = {54, 22, 64, 118, 150, '1x', 56, 76};
            right.Padding = [0 0 0 0];
            right.RowSpacing = 6;
            right.BackgroundColor = P.paper;
            app.TriageLbl = uilabel(right, 'Text', '', 'FontSize', 26, 'FontWeight', 'bold', ...
                'FontColor', [1 1 1], 'HorizontalAlignment', 'center');
            app.FollowLbl = uilabel(right, 'Text', '', 'FontSize', 13, 'FontWeight', 'bold', ...
                'FontColor', P.ink);
            app.MsgLbl = uilabel(right, 'Text', '', 'FontSize', 13, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top', 'FontColor', P.inkSoft);
            app.FoundLbl = uilabel(right, 'Text', '', 'FontSize', 13, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top', 'Interpreter', 'html');
            app.ProbAx = uiaxes(right);
            app.ProbAx.Toolbar.Visible = 'off';
            disableDefaultInteractivity(app.ProbAx);
            app.CritLbl = uilabel(right, 'Text', '', 'FontSize', 12.5, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top', 'Interpreter', 'html');
            app.WhyLbl = uilabel(right, 'Text', '', 'FontSize', 12, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top', 'FontColor', P.inkSoft);
            app.QualityLbl = uilabel(right, 'Text', '', 'FontSize', 12.5, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top', 'Interpreter', 'html');

            app.StatusLbl = uilabel(g, 'Text', '', 'FontSize', 12, 'FontColor', P.inkSoft);
            app.StatusLbl.Layout.Row = 3; app.StatusLbl.Layout.Column = [1 2];
        end

        function showEmpty(app)
            P = app.Pal;
            cla(app.Ax);
            app.Ax.XLim = [0 1]; app.Ax.YLim = [0 1];
            text(app.Ax, 0.5, 0.55, 'Open a photograph of the back of the eye', ...
                'HorizontalAlignment', 'center', 'FontSize', 18, 'FontWeight', 'bold', 'Color', P.ink);
            text(app.Ax, 0.5, 0.47, 'or check a practice eye. Everything runs on this computer.', ...
                'HorizontalAlignment', 'center', 'FontSize', 13, 'Color', P.inkSoft);
            app.TriageLbl.Text = 'No eye checked yet';
            app.TriageLbl.BackgroundColor = P.inkSoft;
            app.FollowLbl.Text = '';
            app.MsgLbl.Text = '';
            app.FoundLbl.Text = '';
            cla(app.ProbAx);
            app.ProbAx.Visible = 'off';
            app.CritLbl.Text = '';
            app.WhyLbl.Text = '';
            app.QualityLbl.Text = '';
            app.MarksBox.Enable = 'off';
            app.SaveBtn.Enable = 'off';
            app.QueueBtn.Enable = 'off';
            app.StatusLbl.Text = sprintf('  NetraSetu %s  |  graders: %s', netra.version(), graders(app.Models.status));
        end

        function show(app)
            R = app.Result;
            P = app.Pal;
            T = R.decision;
            graded = isfield(R, 'fusion');
            app.TriageLbl.Text = strrep(T.triage, '_', ' ');
            app.TriageLbl.BackgroundColor = T.colour;
            app.FollowLbl.Text = T.followUp;
            app.MsgLbl.Text = sprintf('%s\n%s', T.message.en, T.message.hi);
            app.MarksBox.Enable = onOff(graded);
            app.drawImage();
            app.FoundLbl.Text = foundHTML(R, P);
            app.drawProbabilities();
            app.CritLbl.Text = criteriaHTML(R, P);
            if isempty(T.reasons)
                app.WhyLbl.Text = '';
            else
                app.WhyLbl.Text = ['Why: ' strjoin(T.reasons, '; ')];
            end
            app.QualityLbl.Text = qualityHTML(R, P);
            app.SaveBtn.Enable = onOff(graded);
            app.QueueBtn.Enable = 'on';
            app.StatusLbl.Text = sprintf('  %s  |  screened in %.1f s  |  graders: %s', ...
                R.meta.id, R.timing.total, graders(R.models));
        end

        function drawImage(app)
            R = app.Result;
            if isempty(R)
                return
            end
            if isfield(R, 'overlay')
                if app.MarksBox.Value
                    img = R.overlay;
                else
                    img = R.canvas.rgb;
                end
                img = cropFOV(img, R.canvas);
            else
                img = R.thumbnail;
            end
            cla(app.Ax);
            image(app.Ax, im2uint8(img));
            axis(app.Ax, 'image');
            app.Ax.XTick = []; app.Ax.YTick = [];
        end

        function drawProbabilities(app)
            ax = app.ProbAx;
            cla(ax);
            R = app.Result;
            P = app.Pal;
            if ~isfield(R, 'fusion')
                ax.Visible = 'off';
                return
            end
            ax.Visible = 'on';
            p = R.fusion.P;
            hold(ax, 'on');
            for k = 1:5
                bar(ax, k - 1, p(k), 0.6, 'FaceColor', P.grades(k, :), 'EdgeColor', 'none');
                text(ax, k - 1, p(k) + 0.07, sprintf('%.0f%%', 100 * p(k)), ...
                    'HorizontalAlignment', 'center', 'FontSize', 10);
            end
            cs = R.conformalSet;
            if ~isempty(cs) && any(cs)
                f = find(cs, 1, 'first') - 1;
                l = find(cs, 1, 'last') - 1;
                plot(ax, [f - 0.35 l + 0.35], [1.14 1.14], 'k-', 'LineWidth', 1.5);
                text(ax, (f + l) / 2, 1.22, 'conformal set', 'HorizontalAlignment', 'center', ...
                    'FontSize', 9);
            end
            hold(ax, 'off');
            ax.XLim = [-0.6 4.6];
            ax.YLim = [0 1.32];
            ax.XTick = 0:4;
            ax.XTickLabel = {'0 none', '1 mild', '2 mod', '3 sev', '4 PDR'};
            ax.YTick = [];
            ax.Box = 'off';
            ax.Color = P.paper;
            title(ax, sprintf('ICDR grade %d   |   P(referable) %.2f', R.fusion.grade, ...
                R.decision.pReferable), 'FontSize', 12);
        end

        function openDialog(app)
            [f, p] = uigetfile({'*.jpg;*.jpeg;*.png;*.tif;*.tiff;*.bmp', ...
                'Fundus photographs (*.jpg, *.png, *.tif, *.bmp)'; '*.*', 'All files'}, ...
                'Open a fundus photograph');
            figure(app.Fig);
            if isequal(f, 0)
                return
            end
            app.openFile(fullfile(p, f));
        end

        function practice(app)
            g = app.PracticeDrop.Value;
            rgb = netra.phantom.generate('Grade', g, 'Seed', 40 + g, 'Size', 1024);
            app.screenImage(rgb, sprintf('PRACTICE-G%d', g), '');
        end

        function toQueue(app)
            if isempty(app.Result)
                return
            end
            folder = uigetdir(pwd, 'Reader queue folder');
            figure(app.Fig);
            if isequal(folder, 0)
                return
            end
            file = netra.ui.exportCase(app.Result, folder);
            app.StatusLbl.Text = sprintf('  Queued for review: %s  (open with netra.ui.ReaderConsole(''%s''))', ...
                file, folder);
        end

        function onKey(app, evt)
            switch lower(evt.Key)
                case 'o'
                    app.openDialog();
                case 'p'
                    app.practice();
                case 'm'
                    if strcmp(app.MarksBox.Enable, 'on')
                        app.MarksBox.Value = ~app.MarksBox.Value;
                        app.drawImage();
                    end
                case 's'
                    app.saveReport();
            end
        end
    end
end

% ======================================================================
function closeDialog(d)
if isvalid(d)
    close(d);
end
end

function s = onOff(tf)
if tf
    s = 'on';
else
    s = 'off';
end
end

function s = graders(status)
names = {'rules'};
if isstruct(status)
    if isfield(status, 'lesion') && status.lesion, names{end + 1} = 'lesion ensemble'; end
    if isfield(status, 'cnn') && status.cnn, names{end + 1} = 'CNN'; end
end
s = strjoin(names, ' + ');
end

function img = cropFOV(img, cv)
c = cv.centre;
r = cv.radius * 1.01;
D = size(img, 1);
r1 = max(1, round(c(2) - r)); r2 = min(D, round(c(2) + r));
c1 = max(1, round(c(1) - r)); c2 = min(D, round(c(1) + r));
img = img(r1:r2, c1:c2, :);
end

function h = hexOf(col)
h = sprintf('#%02X%02X%02X', round(255 * col));
end

function h = foundHTML(R, P)
if ~isfield(R, 'lesions')
    h = '<div style="color:#6B7280">Not graded: the photograph must be retaken.</div>';
    return
end
s = R.lesions.summary;
he = s.heCounts;
rows = {
    P.ma,      'Microaneurysms',    s.maCount,                           ''
    P.blot,    'Haemorrhages',      s.heTotal + s.preretinalCount,       sprintf('%d dot, %d blot, %d flame, %d pre-retinal', he.dot, he.blot, he.flame, he.preretinal)
    P.exudate, 'Hard exudates',     s.exCount,                           sprintf('macular oedema risk %d', s.dme)
    P.cws,     'Cotton-wool spots', s.cwsCount,                          ''
    };
h = '';
for k = 1:size(rows, 1)
    n = rows{k, 3};
    extra = '';
    if n > 0 && ~isempty(rows{k, 4})
        extra = [' <span style="color:#6B7280">(' rows{k, 4} ')</span>'];
    end
    h = [h sprintf('<div><span style="color:%s">&#9679;</span> %s <b>%d</b>%s</div>', ...
        hexOf(rows{k, 1}), rows{k, 2}, n, extra)]; %#ok<AGROW>
end
nv = {};
if s.nvdProb >= 0.5, nv{end + 1} = 'at the disc'; end
if s.nveProb >= 0.5, nv{end + 1} = 'elsewhere'; end
if ~isempty(nv)
    h = [h sprintf('<div><span style="color:%s">&#9679;</span> <b>New vessels suspected %s</b></div>', ...
        hexOf(P.nv), strjoin(nv, ' and '))];
end
if ~isempty(s.vbQuadrants)
    h = [h sprintf('<div><span style="color:%s">&#9679;</span> Venous beading in %d quadrant(s)</div>', ...
        hexOf(P.vb), numel(s.vbQuadrants))];
end
end

function h = criteriaHTML(R, P)
if ~isfield(R, 'rules')
    h = '';
    return
end
h = '<div style="color:#6B7280"><b>ICDR criteria</b></div>';
C = R.rules.criteria;
for k = 1:numel(C)
    q = C(k);
    if q.met
        h = [h sprintf('<div><span style="color:%s">&#9679;</span> <b>%s</b></div>', ...
            hexOf(P.grades(min(q.level + 1, 5), :)), q.text)]; %#ok<AGROW>
    else
        h = [h sprintf('<div style="color:#9CA3AF">&#9675; %s</div>', q.text)]; %#ok<AGROW>
    end
end
if R.rules.dme >= 1
    h = [h sprintf('<div><span style="color:%s">&#9679;</span> <b>Macular oedema risk %d</b></div>', ...
        hexOf(P.REFER), R.rules.dme)];
end
end

function h = qualityHTML(R, P)
Q = R.quality;
h = sprintf('<div><b>Photo quality %.0f%%</b> (%s)', 100 * Q.score, strrep(Q.decision, '_', ' '));
if isfield(Q, 'enhanced') && Q.enhanced
    h = [h ', enhanced before grading'];
end
h = [h '</div>'];
for k = 1:numel(Q.feedback)
    h = [h sprintf('<div style="color:%s">&#9656; %s</div>', hexOf(P.inkSoft), Q.feedback(k).en)]; %#ok<AGROW>
end
end
