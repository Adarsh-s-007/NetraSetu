function S = scenario(P, maxVans)
%SCENARIO Exogenous inputs of one simulated year, drawn once per seed.
%
%   S = netra.sim.scenario(P) returns hourly series for every POTENTIAL site
%   (P.phc.count PHCs followed by maxVans mobile units, default 6):
%     t, hourOfDay, dow (1 = Monday), month
%     open, closing   site is screening / last screening hour of the day
%     arrivals        Poisson patient arrivals (T x N)
%     linkU           uniform numbers driving the link on/off Markov chains
%     graderOn        reading-hub hours;  ophthOn: ophthalmologist block
%     vanUpload       evening upload window of the mobile units
%     phcUpload       hours in which a PHC's computer is on and uploading
%     tierOfSite      baseline connectivity tier of each PHC (1..4)
%   Decisions (how many PHCs are equipped, link upgrades, AI mode...) are
%   applied later by netra.sim.runReference, so every configuration faces
%   the same patients and the same random outages: comparisons between
%   plans are paired ("common random numbers") and far less noisy.

if nargin < 2
    maxVans = 6;
end
st = rng();
rng(P.seed);
dt = P.dt;
T = round(P.days * 24 / dt);
t = ((0:T - 1)' + 0.5) * dt;                 % hours since Monday 00:00
day = floor(t / 24);
hour = mod(t, 24);
dow = mod(day, 7) + 1;
month = min(12, floor(mod(day, 365) / 30.42) + 1);
Np = P.phc.count;
N = Np + maxVans;

% public holidays: P.phc.holidays per year, pro rata for shorter horizons
holidays = false(max(day) + 1, 1);
cand = find(mod((0:max(day))', 7) < 6);
nHol = min(round(P.phc.holidays * (max(day) + 1) / 364), numel(cand));
holidays(cand(randperm(numel(cand), nHol))) = true;
isHoliday = holidays(day + 1);

openPHC = hour >= P.phc.hours(1) & hour < P.phc.hours(2) & dow <= 6 & ~isHoliday;
closePHC = openPHC & hour + dt >= P.phc.hours(2);
openVan = hour >= P.van.hours(1) & hour < P.van.hours(2) & dow <= P.van.campDaysPerWeek & ~isHoliday;
closeVan = openVan & hour + dt >= P.van.hours(2);
hoursOpen = diff(P.phc.hours);
hoursVan = diff(P.van.hours);

lamPHC = P.phc.demandPerDay / hoursOpen * dt * P.phc.weekday(dow)' .* P.season(month)' .* openPHC;
lamVan = P.van.demandPerCampDay / hoursVan * dt * P.season(month)' .* openVan;
lam = [repmat(lamPHC(:), 1, Np), repmat(lamVan(:), 1, maxVans)];
S = struct();
S.t = t;
S.hourOfDay = hour;
S.dow = dow;
S.month = month;
S.open = [repmat(openPHC, 1, Np), repmat(openVan, 1, maxVans)];
S.closing = [repmat(closePHC, 1, Np), repmat(closeVan, 1, maxVans)];
S.arrivals = reshape(netra.util.poissrnd(lam(:)), T, N);
S.linkU = rand(T, N);
wd = any(S.dow == P.review.graderDays, 2);
S.graderOn = double(hour >= P.review.graderHours(1) & hour < P.review.graderHours(2) & wd & ~isHoliday);
S.ophthOn = double(hour >= P.review.ophthStart & dow <= 5 & ~isHoliday);   % hours capped per day in runReference
S.vanUpload = double(hour >= P.van.uploadHours(1) & hour < P.van.uploadHours(2));
S.phcUpload = double(hour >= P.link.hours(1) & hour < P.link.hours(2) & dow <= 6);
% baseline connectivity of each PHC in proportion to P.link.baselineMix
counts = round(P.link.baselineMix / sum(P.link.baselineMix) * Np);
counts(end) = Np - sum(counts(1:end - 1));
tiers = repelem(1:numel(counts), counts);
S.tierOfSite = tiers(randperm(Np));
S.nPHC = Np;
S.nVanMax = maxVans;
S.T = T;
S.dt = dt;
rng(st);
end
