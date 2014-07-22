function headerInfo = Norpix2files(inpath, outpath, format, range, makedir, showImg)
% Convert n-bit Norpix image to sequence of image files
%
% Based on Norpix2MATLAB by Brett Shoelson@mathworks
%
% ARGUMENTS:
%    INPUTS:
%       INPATH: Path of .seq file, or a folder containing a single .seq file
%       OUTPATH: Path of directory to store output images (set to [] to not
%                output anything -- useful to just show images)
%       FORMAT: String containing image type, accepts
%               'png' (default),'tiff','bmp','jpg'
%       RANGE: Give a 1x2 range of frames to parse. Based on sequential position,
%              timestamps are not guaranteed to be synchronised.
%              Indexed from 1, e.g.
%              []         -- parse all frames
%              [100 Inf]  -- parse frames 100 to end
%              [1 100]    -- parse frames start to 100 (== [0 100] == [-Inf 100])
%              [101 200]  -- parse frames 101 to 200 (inclusive)
%              [Inf Inf]  -- don't parse any frames (just header)
%              Note: timestamps are stored with the images, so they will only be
%              parsed and returned for images in range.
%       MAKEDIR: Creates the directory if it does not exist (default: false)
%       SHOWIMG: Displays the images to a figure (default: false)
%    OUTPUTS:
%       HEADERINFO: Structure containing the information stored in the header
%
% Written 2014/06/11 by Andrew Chinery

% Input sanity check
if nargin < 2
    error('Requires input and output arguments.');
end
if nargin < 3
    format = 'png';
end
if nargin < 4
    range = [];
end
if nargin < 5
    makedir = false;
end
if nargin < 6
    showImg = false;
end

if(exist(inpath,'dir'))
    if(inpath(end) ~= '/')
        inpath(end+1) = '/';
    end
    path = dir([inpath '*.seq']);
    if(length(path) > 1)
        error('Not equipped to handle multiple seq files in a folder');
    elseif(isempty(path))
        error('No seq file found in this folder');
    end
    inpath = [inpath path(1).name];
end

if(~exist(inpath,'file'))
    error('Specified input file does not exist');
end

if(isempty(outpath))
    warning('Outpath is empty, function will not output anything')
elseif(~exist(outpath,'dir'))
    if(makedir)
        mkdir(outpath);
    else
        error('Specified output folder does not exist (create the folder or set makedir true)')
    end
end

if(~any(strcmp(format,{'png','tiff','bmp','jpg'})))
   error('Valid options for format are  ''png'',''tiff'',''bmp'',''jpg''');
end

% Open file for reading
fid = fopen(inpath,'r','b');


% HEADER INFORMATION
% OBF = {Offset (bytes), Bytes, Format}
endianType = 'ieee-le';

% Read header

OFB = {28,1,'long'};
fseek(fid,OFB{1}, 'bof');
headerInfo.Version = fread(fid, OFB{2}, OFB{3}, endianType);
% headerInfo.Version

%
OFB = {32,4/4,'long'};
fseek(fid,OFB{1}, 'bof');
headerInfo.HeaderSize = fread(fid,OFB{2},OFB{3}, endianType);
% headerInfo.HeaderSize

%
OFB = {592,1,'long'};
fseek(fid,OFB{1}, 'bof');
DescriptionFormat = fread(fid,OFB{2},OFB{3}, endianType)';
OFB = {36,512,'ushort'};
fseek(fid,OFB{1}, 'bof');
headerInfo.Description = fread(fid,OFB{2},OFB{3}, endianType)';
if DescriptionFormat == 0 %#ok Unicode
    headerInfo.Description = native2unicode(headerInfo.Description);
elseif DescriptionFormat == 1 %#ok ASCII
    headerInfo.Description = char(headerInfo.Description);
end
% headerInfo.Description

%
OFB = {548,24,'uint32'};
fseek(fid,OFB{1}, 'bof');
tmp = fread(fid,OFB{2},OFB{3}, 0, endianType);
headerInfo.ImageWidth = tmp(1);
headerInfo.ImageHeight = tmp(2);
headerInfo.ImageBitDepth = tmp(3);
headerInfo.ImageBitDepthReal = tmp(4);
headerInfo.ImageSizeBytes = tmp(5);
vals = [0,100,101,200:100:900];
fmts = {'Unknown','Monochrome','Raw Bayer','BGR','Planar','RGB',...
    'BGRx', 'YUV422', 'UVY422', 'UVY411', 'UVY444'};
headerInfo.ImageFormat = fmts{vals == tmp(6)};

%
OFB = {572,1,'ushort'};
fseek(fid,OFB{1}, 'bof');
headerInfo.AllocatedFrames = fread(fid,OFB{2},OFB{3}, endianType);
% headerInfo.AllocatedFrames

%
OFB = {576,1,'ushort'};
fseek(fid,OFB{1}, 'bof');
headerInfo.Origin = fread(fid,OFB{2},OFB{3}, endianType);
% headerInfo.Origin

%
OFB = {580,1,'ulong'};
fseek(fid,OFB{1}, 'bof');
headerInfo.TrueImageSize = fread(fid,OFB{2},OFB{3}, endianType);
% headerInfo.TrueImageSize

%
OFB = {584,1,'double'};
fseek(fid,OFB{1}, 'bof');
headerInfo.FrameRate = fread(fid,OFB{2},OFB{3}, endianType);
% headerInfo.FrameRate

bitstr = '';

% PREALLOCATION
switch headerInfo.ImageBitDepthReal
    case 8
        bitstr = 'uint8';
    case {12,14,16}
        bitstr = 'uint16';
end
if isempty(bitstr)
    error('Unsupported bit depth');
end

% chin: work with colour
switch headerInfo.ImageFormat
    case {'RGB', 'BGR'}
        channels = 3;
    case {'Monochrome','Raw Bayer'}
        channels = 1;
    otherwise
        warning('Seq format not neccessarily accounted for, see this line in code')
        channels = 1;
end
imSize = [headerInfo.ImageWidth,headerInfo.ImageHeight];

if(isempty(range))
    range = [1 headerInfo.AllocatedFrames];
end
if(range(1) < 1)
    range(1) = 1;
end
if(range(2) > headerInfo.AllocatedFrames)
    range(2) = headerInfo.AllocatedFrames;
end

pbar = true; try, progressbar; catch, pbar = false; end %#ok

nread = range(1)-1; % jump to start of selected range
while 1
    % chin: note that header size is currently hardcoded as with N2MATLAB
    headersize = 8192;
    fseek(fid, headersize + nread * headerInfo.TrueImageSize, 'bof');
    frame = fread(fid, channels*headerInfo.ImageWidth * headerInfo.ImageHeight, bitstr, endianType);
    % max(tmp(:))
    if isempty(frame)
        break
    end
    
    tmp = fread(fid, 1, 'int32', endianType);
    tmp2 = fread(fid,2,'uint16', endianType);
    tmp = tmp/86400 + datenum(1970,1,1);
    headerInfo.timestamp{nread-range(1)+2} = [datestr(tmp,'yyyy-mm-ddTHH:MM:SS') ':' sprintf('%03i',tmp2(1)),sprintf('%03i',tmp2(2))];
    %headerInfo.timestamp{nread + 1}

    if(channels > 1)
        frame = permute(reshape(frame,channels,imSize(1),imSize(2)),[3,2,1]);
    else
        frame = permute(reshape(frame,imSize(1),imSize(2),[]),[2,1,3]);
    end

    if(strcmp(headerInfo.ImageFormat,'BGR')) % chin: swap BGR to RGB
        frame(:,:,[3 1]) = frame(:,:,[1 3]);
    elseif(strcmp(headerInfo.ImageFormat,'Raw Bayer'))
        frame = demosaic(uint8(frame), 'gbrg');
    end

    frame = double(frame)./255;

    if(~isempty(outpath))
        imwrite(frame,[outpath strrep(headerInfo.timestamp{nread-range(1)+2},':',';') '.' format]);
    end

    if(showImg)
        figure(2);clf;
        imshow(imresize(frame,0.5,'nearest'));
    end
    
    nread = nread + 1;
    if(pbar)
        progressbar((nread-range(1)+1)/(range(2)-range(1)+1))
    else
        if(mod(nread,100) == 0)
            fprintf('.');
        end
    end
    if(nread >= range(2))
        break;
    end
end
save([outpath 'headerinfo.mat'],'headerInfo');
fprintf('\n');
fclose(fid);
