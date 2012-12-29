classdef PlanarRigidBodyManipulator < RigidBodyManipulator
  % This class wraps the planar pieces of the spatial vector library (v1)
  % provided by Roy Featherstone on his website:
  %   http://users.cecs.anu.edu.au/~roy/spatial/documentation.html
  
  properties
    x_axis_label;
    y_axis_label;
    x_axis;
    y_axis;
    view_axis;
  end
  
  methods
    function obj = PlanarRigidBodyManipulator(urdf_filename,options)
      obj = obj@RigidBodyManipulator();
      obj.D = 2;  % set to 2D

      if (nargin<1) urdf_filename=''; end
      if (nargin<2) options = struct(); end
      if (~isfield(options,'view')) 
        options.view = 'right';
      else
        options.view = lower(options.view);
        if ~any(strcmp(options.view,{'front','right','top'}))
          error('supported view options are front,back,top,bottom,right,or left');
        end
      end
      
      % todo: clean these up.  should they be in "parseURDF?"  should
      % parseURDF even be allowed if it's not called from the constructor (maybe it should be protected)?
      
      switch options.view % joint_axis = view_axis => counter-clockwise
        case 'front'
          obj.x_axis = [0;1;0];
          obj.y_axis = [0;0;1];
          obj.view_axis = [1;0;0];
          obj.x_axis_label='y';
          obj.y_axis_label='z';
          %          obj.name = [obj.name,'Front'];
          obj.gravity = [0;-9.81];
        case 'right'
          obj.x_axis = [1;0;0];
          obj.y_axis = [0;0;1];
          obj.view_axis = [0;1;0];
          obj.x_axis_label='x';
          obj.y_axis_label='z';
          obj.gravity = [0;-9.81];
          %          obj.name = [obj.name,'Right'];
        case 'top'
          obj.x_axis = [1;0;0];
          obj.y_axis = [0;1;0];
          obj.view_axis = [0;0;1];
          obj.x_axis_label='x';
          obj.y_axis_label='y';
          obj.gravity = [0;0];
          %          obj.name = [obj.name,'Top'];
      end
      
      if ~isempty(urdf_filename)
        options.x_axis = obj.x_axis;
        options.y_axis = obj.y_axis;
        options.view_axis = obj.view_axis;
        obj = parseURDF(obj,urdf_filename,options);
      end
    end
    
    function obj = createMexPointer(obj)
      if (obj.mex_model_ptr) deleteMexPointer(obj); end
      obj.mex_model_ptr = HandCpmex(struct(obj),obj.gravity);
    end
    function obj = deleteMexPointer(obj)
      HandCmex(obj.mex_model_ptr);
      obj.mex_model_ptr = 0;
    end
    
    function model=addJoint(model,name,type,parent,child,xyz,rpy,axis,damping,limits,options)
      if (nargin<6) xy=zeros(2,1); end
      if (nargin<7) p=0; end
      if (nargin<9) damping=0; end
      if (nargin<10 || isempty(limits))
        limits = struct();
        limits.joint_limit_min = -Inf;
        limits.joint_limit_max = Inf;
        limits.effort_limit = Inf;
        limits.velocity_limit = Inf;
      end
      
      switch (lower(type))
        case {'revolute','continuous','planar'}
          if abs(dot(axis,model.view_axis))<(1-1e-6)
            warning('Drake:PlanarRigidBodyModel:RemovedJoint',['Welded revolute joint ', child.jointname,' because it did not align with the viewing axis']);
            model = addJoint(model,name,'fixed',parent,child,xyz,rpy,axis,damping,limits,options);
            return;
          end
        case 'prismatic'
          if abs(dot(axis,model.view_axis))>1e-6
            warning('Drake:PlanarRigidBodyModel:RemovedJoint',['Welded prismatic joint ', child.jointname,' because it did not align with the viewing axis']);
            model = addJoint(model,name,'fixed',parent,child,xyz,rpy,axis,damping,limits,options);
            return;
          end
      end
      
      if ~isempty(child.parent)
        error('there is already a joint connecting this child to a parent');
      end
      
      switch (lower(type))
        case {'revolute','continuous'}
          child.pitch=0;
          child.joint_axis=axis;
          child.jsign = sign(dot(axis,model.view_axis));
          if dot(model.view_axis,[0;1;0])  % flip rotational kinematics view='right' to be consistent with vehicle coordinates
            child.jsign = -child.jsign;
          end
          child.jcode=1;
          
        case 'prismatic'
          child.pitch=inf;
          child.joint_axis=axis;
          if abs(dot(axis,model.x_axis))>(1-1e-6)
            child.jcode=2;
            child.jsign = sign(dot(axis,model.x_axis));
          elseif dot(axis,model.y_axis)>(1-1e-6)
            child.jcode=3;
            child.jsign = sign(dot(axis,model.y_axis));
          else
            error('Currently only prismatic joints with their axis in the x-axis or z-axis are supported right now (twoD assumes x-z plane)');
          end
          
        case 'planar'
          % create two links with sliders, then finish this function with
          % the first of these joints (which need to catch the kinematics)
          if (limits.joint_limit_min~=-inf || limits.joint_limit_max~=inf)
            error('joint limits not defined for planar joints');
          end
          jsign = sign(dot(axis,model.view_axis));
          
          body1=newBody(model);
          body1.linkname=[name,'_',model.x_axis_label];
          model.body = [model.body,body1];
          model = addJoint(model,body1.linkname,'prismatic',parent,body1,xyz,rpy,jsign*model.x_axis,damping);
          
          body2=newBody(model);
          body2.linkname=[name,'_',model.y_axis_label];
          model.body = [model.body,body2];
          model = addJoint(model,body2.linkname,'prismatic',body1,body2,zeros(3,1),zeros(3,1),jsign*model.y_axis,damping);
          
          model = addJoint(model,[name,'_p'],'revolute',body2,child,zeros(3,1),zeros(3,1),axis,damping);
          return;
          
        case 'fixed'
          child.pitch=nan;
          
        otherwise
          error(['joint type ',type,' not supported in planar models']);
      end
      
      child.jointname = name;
      child.parent = parent;
      
      wrl_joint_origin='';
      if any(xyz)
        wrl_joint_origin=[wrl_joint_origin,sprintf('\ttranslation %f %f %f\n',xyz(1),xyz(2),xyz(3))];
      end
      if (any(rpy))
        wrl_joint_origin=[wrl_joint_origin,sprintf('\trotation %f %f %f %f\n',rpy2axis(rpy))];
      end
      if ~isempty(wrl_joint_origin)
        child.wrljoint = wrl_joint_origin;
      end
      
      xy = [model.x_axis'; model.y_axis']*xyz;
      if any(rpy)
        rpya=rpy2axis(rpy); p=rpya(4); rpyaxis=rpya(1:3);
        if abs(dot(rpyaxis,model.view_axis))<(1-1e-6)
          warning(['joint ',child.jointname,': joint axes out of the plane are not supported.  the dependent link ',child.linkname,' (and all of it''s decendants) will be zapped']);
          ind = find([model.body]==child);
          model.body(ind)=[];
          return;
          % note that if they were, it would change the way that I have to
          % parse geometries, inertias, etc, for all of the children.
        elseif dot(rpyaxis,model.view_axis)<0
          p=-p;
        end
        if strcmp(options.view,'right')  % flip axis for vehicle coordinates
          p=-p;
        end
      else
        p=0;
      end
      
      child.Xtree = Xpln(p,xy);
      child.Ttree = [rotmat(p),xy; 0,0,1];
      child.T = parent.T*child.Ttree;
      child.damping = damping;
      child.joint_limit_min = limits.joint_limit_min;
      child.joint_limit_max = limits.joint_limit_max;
      child.effort_limit = limits.effort_limit;
      child.velocity_limit = limits.velocity_limit;
    end
    
    function model = addFloatingBase(model)
      rootlink = find(cellfun(@isempty,{model.body.parent}));
      if (length(rootlink)>1)
        warning('multiple root links');
      end
      
      if strcmpi('world',{model.body.linkname})
        error('world link already exists.  cannot add floating base.');
      end
      world = newBody(model);
      world.linkname = 'world';
      world.parent = [];
      model.body = [model.body,world];
      
      limits = struct(); 
      limits.joint_limit_min = -Inf;
      limits.joint_limit_max = Inf;
      limits.effort_limit = Inf;
      limits.velocity_limit = Inf;
      for i=1:length(rootlink)
        model = addJoint(model,model.body(i).linkname,'planar',world,model.body(i),zeros(3,1),zeros(3,1),model.view_axis,0,limits);
      end
    end
    
    function model = compile(model)
      model = compile@RigidBodyManipulator(model);
      model = model.setNumPositionConstraints(2*length(model.loop));
    end
    
    function body = newBody(model)
      body = PlanarRigidBody();
    end
    
    function v=constructVisualizer(obj)
      v = PlanarRigidBodyVisualizer(obj.model);
    end
    
    function phi = positionConstraints(obj,q)
      % so far, only loop constraints are implemented
      phi=loopConstraints(obj,q);
    end
    
    function phi = loopConstraints(obj,q)
      % handle kinematic loops
      % note: each loop adds two constraints
      phi=[];
      jsign = [obj.model.body(cellfun(@(a)~isempty(a),{obj.model.body.parent})).jsign]';
      q = jsign.*q;
      
      for i=1:length(obj.model.loop)
        % for each loop, add the constraints on T1(q) and T2(q), // todo: finish this
        % where
        % T1 is the transformation from the least common ancestor to the
        % constraint in link1 coordinates
        % T2 is the transformation from the least common ancester to the
        % constraint in link2 coordinates
        loop=obj.model.loop(i);
        
        T1 = loop.T1;
        b=loop.body1;
        while (b~=loop.least_common_ancestor)
          TJ = Tjcalcp(b.jcode,q(b.dofnum));
          T1 = b.Ttree*TJ*T1;
          b = b.parent;
        end
        T2 = loop.T2;
        b=loop.body2;
        while (b~=loop.least_common_ancestor)
          TJ = Tjcalcp(b.jcode,q(b.dofnum));
          T2 = b.Ttree*TJ*T2;
          b = b.parent;
        end
        
        if (loop.jcode==1)  % pin joint adds constraint that the transformations must match in position at the origin
          phi = [phi; [1,0,0; 0,1,0]*(T1*[0;0;1] - T2*[0;0;1])];
        else
          error('not implemented yet');
        end
      end
    end
  end
  
  methods (Access=protected)
    
    function model = extractFeatherstone(model)
%      m=struct('NB',{},'parent',{},'jcode',{},'Xtree',{},'I',{});
      dof=0;inds=[];
      for i=1:length(model.body)
        if (~isempty(model.body(i).parent))
          dof=dof+1;
          model.body(i).dofnum=dof;
          inds = [inds,i];
        end
      end
      m.NB=length(inds);
      for i=1:m.NB
        b=model.body(inds(i));
        m.parent(i) = b.parent.dofnum;
        m.jcode(i) = b.jcode;
        m.Xtree{i} = b.Xtree;
        m.I{i} = b.I;
        m.damping(i) = b.damping;  % add damping so that it's faster to look up in the dynamics functions.
      end
      model.featherstone = m;
    end    
  
    function model=removeFixedJoints(model)
      fixedind = find(isnan([model.body.pitch]));
      
      for i=fixedind(end:-1:1)  % go backwards, since it is presumably more efficient to start from the bottom of the tree
        body = model.body(i);
        parent = body.parent;
        
        % add geometry into parent
        if (~isempty(body.geometry))
          for j=1:length(body.geometry)
            pts = body.Ttree * [reshape(body.geometry{j}.x,1,[]); reshape(body.geometry{j}.y,1,[]); ones(1,numel(body.geometry{j}.x))];
            body.geometry{j}.x = reshape(pts(1,:),size(body.geometry{j}.x));
            body.geometry{j}.y = reshape(pts(2,:),size(body.geometry{j}.y));
            parent.geometry = {parent.geometry{:},body.geometry{j}};
          end
        end
      end
      
      model = removeFixedJoints@RigidBodyManipulator(model);
    end
    
    
    function model=parseJoint(model,node,options)
      ignore = char(node.getAttribute('drakeIgnore'));
      if strcmp(lower(ignore),'true')
        return;
      end
      
      name = char(node.getAttribute('name'));
      name = regexprep(name, '\.', '_', 'preservecase');

      childNode = node.getElementsByTagName('child').item(0);
      if isempty(childNode) % then it's not the main joint element
        return;
      end
      child = findLink(model,char(childNode.getAttribute('link')));
      
      parentNode = node.getElementsByTagName('parent').item(0);
      parent = findLink(model,char(parentNode.getAttribute('link')),false);
      if (isempty(parent))
        % could have been zapped
        warning(['joint ',name,' parent link is missing or was deleted.  deleting the child link:', child.linkname,'(too)']);
        ind = find([model.body]==child);
        model.body(ind)=[];
        return;
      end
      
      type = char(node.getAttribute('type'));
      xyz=zeros(3,1); rpy=zeros(3,1);
      origin = node.getElementsByTagName('origin').item(0);  % seems to be ok, even if origin tag doesn't exist
      if ~isempty(origin)
        if origin.hasAttribute('xyz')
          xyz = reshape(str2num(char(origin.getAttribute('xyz'))),3,1);
        end
        if origin.hasAttribute('rpy')
          rpy = reshape(str2num(char(origin.getAttribute('rpy'))),3,1);
        end
      end
      axis=[1;0;0];  % default according to URDF documentation
      axisnode = node.getElementsByTagName('axis').item(0);
      if ~isempty(axisnode)
        if axisnode.hasAttribute('xyz')
          axis = reshape(str2num(char(axisnode.getAttribute('xyz'))),3,1);
          axis = axis/(norm(axis)+eps); % normalize
        end
      end
      damping=0;
      dynamics = node.getElementsByTagName('dynamics').item(0);
      if ~isempty(dynamics)
        if dynamics.hasAttribute('damping')
          damping = str2num(char(dynamics.getAttribute('damping')));
        end
      end

      joint_limit_min=-inf;
      joint_limit_max=inf;
      effort_limit=inf;
      velocity_limit=inf;
      limits = node.getElementsByTagName('limit').item(0);
      if ~isempty(limits)
        if limits.hasAttribute('lower')
          joint_limit_min = str2num(char(limits.getAttribute('lower')));
        end
        if limits.hasAttribute('upper');
          joint_limit_max = str2num(char(limits.getAttribute('upper')));
        end          
        if limits.hasAttribute('effort');
          effort_limit = str2num(char(limits.getAttribute('effort')));
        end          
        if limits.hasAttribute('velocity');
          velocity_limit = str2num(char(limits.getAttribute('velocity')));
          warning('Drake:PlanarRigidBodyModel:UnsupportedVelocityLimits','Velocity limits are not supported yet');
        end          
      end

      limits = struct();
      limits.joint_limit_min = joint_limit_min;
      limits.joint_limit_max = joint_limit_max;
      limits.effort_limit = effort_limit;
      limits.velocity_limit = velocity_limit;
      
      model = addJoint(model,name,type,parent,child,xyz,rpy,axis,damping,limits,options);
    end
    
    function model = parseLoopJoint(model,node,options)
      loop = PlanarRigidBodyLoop();
      loop.name = char(node.getAttribute('name'));
      loop.name = regexprep(loop.name, '\.', '_', 'preservecase');

      link1Node = node.getElementsByTagName('link1').item(0);
      link1 = findLink(model,char(link1Node.getAttribute('link')));
      loop.body1 = link1;
      loop.T1 = loop.parseLink(link1Node,options);
      
      link2Node = node.getElementsByTagName('link2').item(0);
      link2 = findLink(model,char(link2Node.getAttribute('link')));
      loop.body2 = link2;
      loop.T2 = loop.parseLink(link2Node,options);
      
      %% find the lowest common ancestor
      loop.least_common_ancestor = leastCommonAncestor(loop.body1,loop.body2);

      axis=[1;0;0];  % default according to URDF documentation
      axisnode = node.getElementsByTagName('axis').item(0);
      if ~isempty(axisnode)
        if axisnode.hasAttribute('xyz')
          axis = reshape(str2num(char(axisnode.getAttribute('xyz'))),3,1);
          axis = axis/(norm(axis)+eps); % normalize
        end
      end
      
      type = char(node.getAttribute('type'));
      switch (lower(type))
        case {'revolute','continuous'}
          loop.jcode=1;          
          if dot(axis,model.view_axis)<(1-1e-6)
            axis
            model.view_axis
            error('revolute joints must align with the viewing axis');
            % note: i don't support negative angles here yet (via jsign),
            % but could
          end

        case 'prismatic'
          if dot(axis,model.x_axis)>(1-1e-6)
            loop.jcode=2;
          elseif dot(axis,model.y_axis)>(1-1e-6)
            loop.jcode=3;
          else
            error('axis must be aligned with x or z');
            % note: i don't support negative angles here yet (via jsign),
            % but could
          end
        otherwise
          error(['joint type ',type,' not supported (yet?)']);
      end
      
      model.loop=[model.loop,loop];
    end
    
  end
  
end
