function hazard=climada_cosmoensemble2hazard(cosmo_filename,params,entity)
% climada cosmo winterstorm europe Switzerland netcdf
% MODULE:
%   storm_europe
% NAME:
%   climada_cosmoensemble2hazard
% PURPOSE:

%   read COSMO ensemble windfields from netCDF and store into climada hazard structure, 

%   ready for movie generation, if an entity is passed on, too.
%
%   next call: climada_hazard_stats, climada_event_damage_animation
% CALLING SEQUENCE:
%   hazard=climada_cosmoensemble2hazard(cosmo_filename,params,entity)
% EXAMPLE:
%   
%
%   LATEST
%   p.focus_region=[4 13 45 49];p.asset_markersize=4;p.schematic_tag=1;p.axis_equal=0;
%   p.npoints=799;p.Position=[1 1 3840 2160];climada_event_damage_animation('',p)
%
%   params=climada_cosmoensemble2hazard('params') % return default parameters

% INPUTS:
%   cosmo_filename: filename of the netCDF file with COSMO output
%       > promted for if not given, path and .nc appended if missing
%       If ='params', return default params structure
%       If ='TEST', run test mode
%       If ='DEF', use default file, see PARAMETERS
% OPTIONAL INPUT PARAMETERS:
%   params: a structure with fields (see also tc_track='params' above):
%    windspeed_threshold: above which wind speeds are kept in hazard set
%       Default =20, since no damages below anyway
%    damage_threshold: above which damages at single centroids are kept
%       Default =1000 Value units, speeds up visualization
%    hazard_filename: the filename the hazard structure will be saved to
%    animation_data: the filename the anaimation data will be saved to,
%       default is animation_data.mat in the climada results folder.
%    test_mode: default=0
%       >0: use only a few timesteps
%       abs(.)>1: run movie generation automatically after generating the data
%    focus_region: the region we're going to show [minlon maxlon minlat maxlat]
%       default=[], automatically determined by area of data lat/lon
%    hazard_density: the sparse intensity array density, default=.01
%    damage_cumsum: if =1, store cumulative damage over time, default=0
%    time_range: specify the time range that should go into the hazard,
%       format is a vector with two "datenum" dates 
%   entity: a climada entity structure, e.g. from entity=climada_entity_load
%       is passed, the animation data file is created, i.e. strong the
%       assets to hazard in the hazard.assets and the resulting damage in
%       hazard.damage. See climada_event_damage_animation
% OUTPUTS:
%   hazard: a climada hazard set, if entity passed including the fields
%       needed for animation generation, i.e. hazard.damage and hazard.assets
% MODIFICATION HISTORY:
% Thomas R??sli, thomas.roeoesli@usys.ethz.ch, 20181017, initial, based on climada_cosmo2hazard by David N. Bresch, david.bresch@gmail.com, 20170707
%-

hazard=[]; % init output

global climada_global
if ~climada_init_vars,return;end % init/import global variables

% poor man's version to check arguments
% and to set default value where  appropriate
if ~exist('cosmo_filename','var'),cosmo_filename='';end
if ~exist('params','var'),params=struct;end % in case we want to pass all parameters as structure
if ~exist('entity','var'),entity=[];end

% check for some parameter fields we need
if ~isfield(params,'hazard_density'),      params.hazard_density=[];end
if ~isfield(params,'windspeed_threshold'), params.windspeed_threshold=[];end
if ~isfield(params,'damage_threshold'),    params.damage_threshold=[];end
if ~isfield(params,'hazard_filename'),     params.hazard_filename='';end
if ~isfield(params,'animation_data'),      params.animation_data='';end
if ~isfield(params,'test_mode'),           params.test_mode=[];end
if ~isfield(params,'focus_region'),        params.focus_region=[];end
if ~isfield(params,'damage_cumsum'),       params.damage_cumsum=[];end
if ~isfield(params,'time_range'),          params.time_range=[];end

% locate the module's (or this code's) data folder (usually  a folder
% 'parallel' to the code folder, i.e. in the same level as code folder)
%module_data_dir=[fileparts(fileparts(mfilename('fullpath'))) filesep 'data'];

% PARAMETERS
%
% set default values (see header for details)
%
if isempty(params.hazard_density),      params.hazard_density=0.01;end
if isempty(params.windspeed_threshold), params.windspeed_threshold=20;end % m/s
if isempty(params.damage_threshold),    params.damage_threshold=1000;end % Value units
if isempty(params.hazard_filename),     params.hazard_filename='CHE_MeteoSwiss_WS';end % [climada_global.hazards_dir filesep 'CHE_MeteoSwiss_WS'];end
if isempty(params.animation_data),      params.animation_data=[climada_global.results_dir filesep 'animation_data'];end
if isempty(params.test_mode),           params.test_mode=0;end
if isempty(params.focus_region),        params.focus_region=[];end
if isempty(params.damage_cumsum),       params.damage_cumsum=0;end
%
%cosmo_filename_DEF=[climada_global.data_dir filesep 'MeteoSwiss' filesep 'cosmo1_1999122500.nc'];
cosmo_filename_DEF=['D:' filesep 'Documents_DATA' filesep 'Cosmo' filesep 'Wind' filesep 'Lothar' filesep 'cosmo1_1999122500.nc'];
    
if strcmpi(cosmo_filename,'params'),hazard=params;return;end % special case, return the full parameters strcture
if strcmpi(cosmo_filename,'TEST')
    cosmo_filename=cosmo_filename_DEF;
    params.test_mode=1;
    params.focus_region=[4 12 45 48];
end
if strcmpi(cosmo_filename,'DEF'),cosmo_filename=cosmo_filename_DEF;end


% prompt for cosmo_filename if not given
if isempty(cosmo_filename) % local GUI
    cosmo_filename=[climada_global.data_dir filesep '*.nc'];
    [filename, pathname] = uigetfile(cosmo_filename, 'Open:');
    if isequal(filename,0) || isequal(pathname,0)
        return; % cancel
    else
        cosmo_filename=fullfile(pathname,filename);
    end
end

[fP,fN,fE]=fileparts(cosmo_filename);
if isempty(fN),fN=[climada_global.data_dir filesep 'MeteoSwiss'];end
if isempty(fE),fE='.nc';end
cosmo_filename=[fP filesep fN fE];

% get data from netCDF
nc.info  = ncinfo(cosmo_filename);
nc.lon   = ncread(cosmo_filename,'lon_1')';
nc.lat   = ncread(cosmo_filename,'lat_1')';
nc.time  = ncread(cosmo_filename,'time')';
nc.eps   = ncread(cosmo_filename,'epsd_1')';

n_times=length(nc.time);

% check if which timesteps are within the given range defined by params.time_range
time_start = 1;
time_count = Inf;
nc.datenum = datenum(...
    nc.info.Variables(... % this selects the starting point of the Cosmo-Run within the netcdf
    strcmp({nc.info.Variables.Name},'time'))...
    .Attributes(strcmp({nc.info.Variables(strcmp({nc.info.Variables.Name},'time')).Attributes.Name},'units'))...
    .Value(15:end)... % this selects the starting point of the Cosmo-Run within the netcdf - end
    ,'yyyy-mm-dd HH:MM:SS') + (nc.time/24/60/60);
if ~isempty(params.time_range)
    time_within_range = true(size(nc.time)) & (nc.datenum >= params.time_range(1));
    time_within_range = time_within_range & (nc.datenum < params.time_range(2));
    if ~any(time_within_range)
        error('params.time_range wrongly defined. no data within specified time range.');
    end
    time_start = find(time_within_range,1,'first');
    time_count = find(time_within_range,1,'last') - time_start + 1;
    n_times = sum(time_within_range);
end
    

%if size(nc.lat,2)==1,[nc.lat,nc.lon] = meshgrid(nc.lat,nc.lon);end
% calculate area per centroid
nc.area_km2=abs(nc.lon(2:end,2:end)-nc.lon(1:end-1,1:end-1))...
    .*cos(nc.lat(1:end-1,1:end-1)./180.*pi)*111.12 .* ...
    abs(nc.lat(2:end,2:end)-nc.lat(1:end-1,1:end-1))*111.12;
nc.area_km2(end+1,:)=nc.area_km2(end,:); % fill last row/column
nc.area_km2(:,end+1)=nc.area_km2(:,end); % fill last row/column

if params.test_mode>0 % restrict to a few timesteps
%     t1=max(floor(n_times/2-3),1);
%     t2=min(ceil(n_times/2+3),n_times);
%     nc.time=nc.time(t1:t2);
time_count = min(3,min(n_times,time_count)); % only read 3 timesteps
end

hazard.lon=double(reshape(nc.lon,[1 numel(nc.lon)])); % as 1-D vect
hazard.lat=double(reshape(nc.lat,[1 numel(nc.lon)])); % as 1-D vect

% restrict area to focus region
if ~isempty(params.focus_region)
    edges_x = [params.focus_region(1),params.focus_region(1),params.focus_region(2),params.focus_region(2),params.focus_region(1)];
    edges_y = [params.focus_region(3),params.focus_region(4),params.focus_region(4),params.focus_region(3),params.focus_region(3)];
    inp = inpolygon(hazard.lon,hazard.lat,edges_x,edges_y);
    hazard.lon=hazard.lon(inp);
    hazard.lat=hazard.lat(inp);
    hazard.focus_region=params.focus_region;
else
    inp=[];
end

n_centroids=length(hazard.lon);

n_ensembles=length(nc.eps); % as we might need to interpolate later from original times

hazard.intensity=spalloc(n_ensembles,n_centroids,ceil(n_ensembles*n_centroids*params.hazard_density));

fprintf('processing %i events (timesteps) at %i centroids (v>%im/s)\n',n_ensembles,n_centroids,params.windspeed_threshold);
climada_progress2stdout    % init, see terminate below
for ensemble_i=1:n_ensembles
    temp_data  = ncread(cosmo_filename,'VMAX_10M',[1 1 ensemble_i time_start],[Inf Inf 1 time_count]); % only one time slab
    temp_data = squeeze(max(temp_data,[],4));
    temp_data=reshape(temp_data',[1 numel(temp_data)]); % as 1-D vect
    
    if ~isempty(inp),temp_data=temp_data(inp);end
    
    % to check, use e.g.
    %climada_color_plot(temp_data,hazard.lon,hazard.lat,'','','','',600)

    nzp=temp_data>params.windspeed_threshold;
    hazard.intensity(ensemble_i,nzp)=temp_data(nzp);
    climada_progress2stdout(ensemble_i,n_ensembles,10,'events'); % update

end % time_i
climada_progress2stdout(0) % terminate

% complete hazard structure
hazard.centroid_ID      = 1:n_centroids;
hazard.peril_ID         = 'WS';
hazard.units            = 'm/s';
hazard.date             = datestr(now);
hazard.filename         = params.hazard_filename;
hazard.reference_year   = climada_global.present_reference_year;
hazard.event_ID         = 1:n_ensembles;
hazard.event_count      = n_ensembles;
hazard.orig_event_flag  = ones(1,n_ensembles);
hazard.orig_event_count = n_ensembles;
hazard.orig_years       = hazard.event_ID*0+1999;
hazard.frequency        = hazard.event_ID*0+1; % all one
hazard.area_km2         = nc.area_km2;
hazard.yyyy             = repmat(year(nc.datenum(1)),n_ensembles,1);
hazard.mm               = repmat(month(nc.datenum(1)),n_ensembles,1);
hazard.dd               = repmat(day(nc.datenum(1)),n_ensembles,1);
fprintf('saving hazard set in %s\n',hazard.filename);
save([climada_global.hazards_dir filesep hazard.filename],'hazard',climada_global.save_file_version) % for HDF5 format (portability), 20170707

if ~isempty(entity)
    
    entity=climada_assets_encode(entity,hazard);
    
    % add elevation in m
    entity.assets.elevation_m=srtm_elevation_m(entity.assets.lon,entity.assets.lat);
    entity.assets.DamageFunID(entity.assets.elevation_m>1500)=0; % switch off damage calculation above height
    
    % set global parameters (they are reset below)
    climada_global_damage=climada_global.damage_at_centroid;
    climada_global.damage_at_centroid=1;
    EDS=climada_EDS_calc(entity,hazard);
    climada_global.damage_at_centroid=climada_global_damage; % reset
    EDS.damage_at_centroid(EDS.damage_at_centroid<params.damage_threshold)=0;
    hazard.damage=sparse(EDS.damage_at_centroid)';
    
    if params.damage_cumsum,hazard.damage = cumsum(hazard.damage,1);end
    
    hazard.assets.lon=entity.assets.lon;
    hazard.assets.lat=entity.assets.lat;
    hazard.assets.Value=entity.assets.Value;
    
    fprintf('saving animation data in %s\n',params.animation_data);
    save(params.animation_data,'hazard',climada_global.save_file_version) % for HDF5 format (portability), 20170707
    
    if abs(params.test_mode)>1
        params.resolution_km=1;
        params.asset_markersize=1;
        params.schematic_tag=-2;
        params.npoints=399;
        climada_event_damage_animation(params.animation_data,params);
    end
end % ~isempty(entity)

end % climada_cosmo2hazard