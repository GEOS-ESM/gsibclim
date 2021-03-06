module m_gsibclim

!use mpi

use constants, only: zero,one
use m_kinds, only: i_kind,r_kind
use m_mpimod, only: npe,mype,mpi_character,gsi_mpi_comm_world
use m_mpimod, only: setworld
use gridmod, only: nlon,nlat,lon2,lat2,lat1,lon1,nsig
use guess_grids, only: nfldsig
use guess_grids, only: guess_grids_init
use guess_grids, only: guess_grids_final
!use guess_grids, only: gsiguess_bkgcov_init
use guess_grids, only: gsiguess_bkgcov_final
use state_vectors, only: allocate_state,deallocate_state
use control_vectors, only: control_vector
use control_vectors, only: allocate_cv,deallocate_cv
use control_vectors, only: assignment(=)
use control_vectors, only: cvars3d
use control_vectors, only: prt_control_norms
use control_vectors, only: inquire_cv
use control_vectors, only: cvars2d, cvars3d
use bias_predictors, only: predictors,allocate_preds,deallocate_preds,assignment(=)
use gsi_bundlemod, only: gsi_bundle
use gsi_bundlemod, only: gsi_bundlegetpointer
use gsi_bundlemod, only: gsi_bundleprint
use gsi_bundlemod, only: assignment(=)
use mpeu_util, only: die
use m_mpimod, only: nxpe,nype
use gsimod, only: gsimain_initialize
use gsimod, only: gsimain_finalize
use berror, only: simcv,bkgv_write_cv,bkgv_write_sv
use m_berror_stats,only : berror_stats
use gsi_4dvar, only: nsubwin
use jfunc, only: nsclen,npclen,ntclen
use general_sub2grid_mod, only: sub2grid_info
use general_sub2grid_mod, only: general_sub2grid_create_info
use general_sub2grid_mod, only: general_sub2grid_destroy_info

implicit none

private
public gsibclim_init
public gsibclim_cv_space
public gsibclim_sv_space
public gsibclim_befname
public gsibclim_final

interface gsibclim_init
  module procedure init_
end interface gsibclim_init

interface gsibclim_cv_space
  module procedure be_cv_space0_
  module procedure be_cv_space1_
end interface gsibclim_cv_space

interface gsibclim_sv_space
  module procedure be_sv_space0_
  module procedure be_sv_space1_
end interface gsibclim_sv_space

interface gsibclim_befname
  module procedure befname_
end interface gsibclim_befname

interface gsibclim_final
  module procedure final_
end interface gsibclim_final

logical :: initialized_ = .false.
logical :: iamset_ = .false.

character(len=*), parameter :: myname ="m_gsibclim"
contains
  subroutine init_(cv,lat2out,lon2out,mockbkg,nmlfile,befile,layout,comm)

  logical, intent(out) :: cv
  integer, intent(out) :: lat2out,lon2out
  logical, intent(in)  :: mockbkg
  character(len=*),optional,intent(in) :: nmlfile
  character(len=*),optional,intent(in) :: befile
  integer,optional,intent(in) :: layout(2) ! 1=nx, 2=ny
  integer,optional,intent(in) :: comm

  character(len=*), parameter :: myname_=myname//"init_"
  type(sub2grid_info) :: sg
  integer :: ier
  logical :: already_init_mpi

  if (initialized_) then
     call final_(.false.) ! finalize what should have been finalized
  endif

  ier=0
  call mpi_initialized(already_init_mpi,ier)
  if(ier/=0) call die(myname,'mpi_initialized(), ieror =',ier)
  if(.not.already_init_mpi) then
     call mpi_init(ier)
     if(ier/=0) call die(myname,'mpi_init(), ier =',ier)
  endif
  call setworld(comm=comm)
  call mpi_comm_size(gsi_mpi_comm_world,npe,ier)
  call mpi_comm_rank(gsi_mpi_comm_world,mype,ier)

  if (present(layout)) then
     nxpe=layout(1)
     nype=layout(2)
  endif
  if (present(befile)) then
     call befname_(befile,0)
  endif
  call gsimain_initialize(nmlfile=nmlfile)
  call set_()
  call set_pointer_()
  call guess_grids_init(mockbkg=mockbkg)

! create subdomain/grid indexes 
! call general_sub2grid_create_info(sg,0,nlat,nlon,nsig,1,.false.)
! istart=sg%istart
! jstart=sg%jstart
! call general_sub2grid_destroy_info(sg)
  lat2out=lat2
  lon2out=lon2

  cv = simcv
  initialized_=.true.
  end subroutine init_
!--------------------------------------------------------
  subroutine final_(closempi)

  logical, intent(in) :: closempi

  call gsiguess_bkgcov_final()
  call guess_grids_final()
  call unset_()
  call gsimain_finalize(closempi)
  initialized_=.false.

  end subroutine final_
!--------------------------------------------------------
  subroutine set_

   use constants, only: pi,one,half,rearth
   use gridmod, only: rlats,rlons,wgtlats
   use gridmod, only: coslon,sinlon
   use gridmod, only: rbs2
   use gridmod, only: sp_a
   use gridmod, only: create_grid_vars
   use gridmod, only: use_sp_eqspace
   use compact_diffs, only: cdiff_created
   use compact_diffs, only: cdiff_initialized
   use compact_diffs, only: create_cdiff_coefs
   use compact_diffs, only: inisph
!  use mp_compact_diffs_mod1, only: init_mp_compact_diffs1
!  use compact_diffs, only: uv2vordiv
   implicit none
   real(r_kind) :: dlat,dlon,pih
   integer i,j,i1,ifail

   if (iamset_ ) return

   call create_grid_vars()
   ifail=0
   if(.not.allocated(rlons)) ifail = 1
   if(.not.allocated(rlats)) ifail = 1
   if(ifail/=0) call die('init','dims not alloc', 99)

   if (use_sp_eqspace) then
      dlon=(pi+pi)/nlon    ! in radians
      dlat=pi/(nlat-1)

! Set grid longitude array used by GSI.
      do i=1,nlon                       ! from 0 to 2pi
         rlons (i)=(i-one)*dlon
         coslon(i)=cos(rlons(i))
         sinlon(i)=sin(rlons(i))
      end do

! Set grid latitude array used by GSI.
      pih =half*pi
      do j=1,nlat                       ! from -pi/2 to +pi/2
         rlats(j)=(j-one)*dlat - pih
      end do

! wgtlats is used by spectral code. The values are used as divisor in the
! compact_diffs::inisph() routine.  Therefore, set to TINY instead of ZERO.
!     wgtlats(:)=TINY(wgtlats)
      wgtlats=zero
      do i=sp_a%jb,sp_a%je
         i1=i+1
         wgtlats(i1)=sp_a%wlat(i) !sp_a%clat(i)
         i1=nlat-i
         wgtlats(i1)=sp_a%wlat(i) !sp_a%clat(i)
      end do

! rbs2=1/cos^2(rlats)) is used in pcp.  polar points are set to zeroes.
      rbs2(1       )=zero
      rbs2(2:nlat-1)=cos(rlats(2:nlat-1))
      rbs2(2:nlat-1)=one/(rbs2(2:nlat-1)*rbs2(2:nlat-1))
      rbs2(  nlat  )=zero
   else
      if(mype==0) print *, 'Gaussian Grid in Use'
      call gengrid_vars
   endif

   if(.not.cdiff_created()) call create_cdiff_coefs()
   if(.not.cdiff_initialized()) call inisph(rearth,rlats(2),wgtlats(2),nlon,nlat-2)
!  call init_mp_compact_diffs1(nsig+1,mype,.false.)
   iamset_ = .true.
  end subroutine set_
!--------------------------------------------------------
  subroutine unset_
   use gridmod, only: destroy_grid_vars
   use compact_diffs, only: cdiff_created
   use compact_diffs, only: destroy_cdiff_coefs
   implicit none
   if(cdiff_created()) call destroy_cdiff_coefs
   call destroy_grid_vars
   iamset_ = .false.
  end subroutine unset_
!--------------------------------------------------------
  subroutine set_pointer_
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    set_pointer
!   prgmmr: treadon          org: np23                date: 2004-07-28
!
! abstract: Set length of control vector and other control 
!           vector constants
!
! program history log:
!   2004-07-28  treadon
!   2006-04-21  kleist - include pointers for more time tendency arrays
!   2008-12-04  todling - increase number of 3d fields from 6 to 8 
!   2009-09-16  parrish - add hybrid_ensemble connection in call to setup_control_vectors
!   2010-03-01  zhu     - add nrf_levb and nrf_leve, generalize nval_levs
!                       - generalize vector starting points such as nvpsm, nst2, and others
!   2010-05-23  todling - remove pointers such as nvpsm, nst2, and others (intro on 10/03/01)
!                       - move nrf_levb and nrf_leve to anberror where they are needed
!   2010-05-29  todling - generalized count for number of levels in state variables
!   2013-10-22  todling - revisit level count in view of changes to bundle
!
!   input argument list:
!
!   output argument list:
!
! attributes:
!   language: f90
!   machine:  ibm rs/6000 sp
!
!$$$
    use gridmod, only: latlon11,latlon1n,nsig,lat2,lon2
    use gridmod, only: nlat,nlon
    use state_vectors, only: ns2d,levels
    use constants, only : max_varname_length
    use bias_predictors, only: setup_predictors
    use control_vectors, only: nc2d,nc3d
    use control_vectors, only: setup_control_vectors
    use state_vectors, only: setup_state_vectors
    implicit none

    integer(i_kind) n_ensz,nval_lenz_tot,nval_lenz_enz

    integer(i_kind) n_ens,npred,jpch_rad,npredp,npcptype,nvals_levs,nval_len
    integer(i_kind) nvals_len,nval_levs,nclen,nrclen,nclen1,nclen2,nval2d
    logical lsqrtb

    npred=0
    jpch_rad=0
    npredp=0
    npcptype=0
    lsqrtb=.false.
    n_ens=0

    nvals_levs=ns2d+sum(levels)
    nvals_len=nvals_levs*latlon11

    nval_levs=max(0,nc3d)*nsig+max(0,nc2d)
    nval_len=nval_levs*latlon11
    nsclen=npred*jpch_rad
    npclen=npredp*npcptype
    ntclen=0
    nclen=nsubwin*nval_len+nsclen+npclen+ntclen
    nrclen=nsclen+npclen+ntclen
    nclen1=nclen-nrclen
    nclen2=nclen1+nsclen
  
    n_ensz=0
    nval_lenz_enz=0
    nval2d=latlon11

    CALL setup_control_vectors(nsig,lat2,lon2,latlon11,latlon1n, &
                               nsclen,npclen,ntclen,nclen,nsubwin,nval_len,lsqrtb,n_ens, &
                               nval_lenz_enz)
    CALL setup_predictors(nrclen,nsclen,npclen,ntclen)
    CALL setup_state_vectors(latlon11,latlon1n,nvals_len,lat2,lon2,nsig)

  end subroutine set_pointer_
!--------------------------------------------------------
  subroutine set_silly_(bundle)
  use gsi_bundlemod, only: gsi_bundle
  use gsi_bundlemod, only: gsi_bundlegetpointer
  implicit none
  type(gsi_bundle) bundle
  character(len=*), parameter :: myname_ = myname//'*set_silly_'
  real(r_kind),pointer :: ptr3(:,:,:)=>NULL()
  real(r_kind),pointer :: ptr2(:,:)=>NULL()
  integer k,iset
  integer :: ier
  integer zex(4),zex072(4), zex127(4)
  real(r_kind) :: val
  character(len=2) :: var
  character(len=80):: ifname(1)
  character(len=80):: ofname
! logical :: fexist
!ifname = 'xinc.eta.nc4'
!ofname = 'outvec_bkgtest'
!inquire(file=ifname(1),exist=fexist)
!if(.not.fexist) then
!  call die ('main',': fishy', 99)
!endif
!
  if (mod(mype,6) /= 0) return
!
!            sfc  ~500  ~10   ~1
  zex072 = (/  1,   23,  48,  58 /)
  zex127 = (/  1,   53, 106, 116 /)
  iset=-1
  if (nsig==72) then
    zex=zex072
    iset=1
  endif
  if (nsig==127) then
    zex=zex127
    iset=1
  endif
  val=one
  var='sf'
  var='q'
  var='t'
  var='tv'
  if (iset<0) call die(myname_,'no input set',99)
  call gsi_bundlegetpointer(bundle,trim(var),ptr3,ier)
  if(ier==0) then
     if(var=='sf' .or. var=='vp') then
       val=val*1e-5
     endif
     do k=1,size(zex)
        ptr3(10,10,zex(k)) = val
     enddo
     if (mype==0) print *, myname_, ': var= ', trim(var)
     return
  endif
  if(var == 'tv') then
     call gsi_bundlegetpointer(bundle,trim(var),ptr3,ier)
     if(ier==0) then
        do k=1,size(zex)
           ptr3(10,10,zex(k)) = val
        enddo
        if (mype==0) print *, myname_, ': var= ', trim(var)
        return
     endif
  endif
  if (var == 'ps') then
     call gsi_bundlegetpointer(bundle,'ps',ptr2,ier)
     if(ier==0) then
        ptr2(10,10) = 100.
        if (mype==0) print *, myname_, ': var= ', 'ps'
        return
     endif
  endif
  end subroutine set_silly_
!--------------------------------------------------------
  subroutine be_cv_space0_

  type(control_vector) :: gradx,grady

! apply B to vector: all in control space

! allocate vectors
  call allocate_cv(gradx)
  call allocate_cv(grady)
  gradx=zero
  grady=zero

  call set_silly_(gradx%step(1))

  call bkerror(gradx,grady, &
               1,nsclen,npclen,ntclen)

  if(bkgv_write_cv) &
  call write_bundle(grady%step(1),'cvbundle')

! clean up
  call deallocate_cv(gradx)
  call deallocate_cv(grady)

  end subroutine be_cv_space0_

  subroutine be_cv_space1_(gradx,internalcv,bypassbe)

  type(control_vector) :: gradx
  logical,optional,intent(in) :: internalcv
  logical,optional,intent(in) :: bypassbe

  type(control_vector) :: grady

  logical bypassbe_

  bypassbe_ = .false.
  if (present(bypassbe)) then
     if (bypassbe) bypassbe_ = .true.
  endif

! apply B to vector: all in control space
  if (present(internalcv)) then
     if(internalcv) call set_silly_(gradx%step(1))
  endif

! allocate vectors
  call allocate_cv(grady)

  if (bypassbe_) then
     grady=gradx
  else
     grady=zero
     call bkerror(gradx,grady, &
                  1,nsclen,npclen,ntclen)
  endif

  if(bkgv_write_cv) &
  call write_bundle(grady%step(1),'cvbundle')

! return result in input vector
  gradx=grady

! clean up
  call deallocate_cv(grady)

  end subroutine be_cv_space1_
!--------------------------------------------------------
  subroutine be_sv_space0_

  type(gsi_bundle), allocatable :: fcgrad(:)
  type(control_vector) :: gradx,grady
  type(predictors)     :: sbias
  integer ii

! start work space
  allocate(fcgrad(nsubwin))
  do ii=1,nsubwin
      call allocate_state(fcgrad(ii))
      fcgrad(ii) = zero
  end do
  call allocate_preds(sbias)

  call allocate_cv(gradx)
  call allocate_cv(grady)
  gradx=zero
  grady=zero

! get test vector (fcgrad)
! call get_state_perts_ (fcgrad(1))
!
  call set_silly_(fcgrad(1))

  call control2state_ad(fcgrad,sbias,gradx)

! apply B to input (transformed) vector
  call bkerror(gradx,grady, &
               1,nsclen,npclen,ntclen)

  call control2state(grady,fcgrad,sbias)
  if(bkgv_write_sv) &
  call write_bundle(fcgrad(1),'svbundle')

! clean up work space
  call deallocate_cv(gradx)
  call deallocate_cv(grady)
  call deallocate_preds(sbias)
  do ii=1,nsubwin
      call deallocate_state(fcgrad(ii))
  end do
  deallocate(fcgrad)

  end subroutine be_sv_space0_
!--------------------------------------------------------
  subroutine be_sv_space1_(fcgrad,internalsv,bypassbe)

  type(gsi_bundle) :: fcgrad(1)
  logical,optional,intent(in) :: internalsv
  logical,optional,intent(in) :: bypassbe

  type(control_vector) :: gradx,grady
  type(predictors)     :: sbias
  logical bypassbe_
  integer ii,ier

  if (nsubwin/=1) then
     if(ier/=0) call die(myname,'cannot handle this nsubwin =',nsubwin)
  endif

  bypassbe_ = .false.
  if (present(bypassbe)) then
     if (bypassbe) bypassbe_ = .true.
  endif

! start work space
  call allocate_preds(sbias)
  call allocate_cv(gradx)
  call allocate_cv(grady)
  gradx=zero
  grady=zero

! get test vector (fcgrad)
! call get_state_perts_ (fcgrad(1))
  if (present(internalsv)) then
     if (internalsv) call set_silly_(fcgrad(1))
  endif

  call control2state_ad(fcgrad,sbias,gradx)

! apply B to input (transformed) vector
  if (bypassbe_) then
    grady=gradx
  else
    call bkerror(gradx,grady, &
                 1,nsclen,npclen,ntclen)
  endif

  call control2state(grady,fcgrad,sbias)
  if(bkgv_write_sv) &
  call write_bundle(fcgrad(1),'svbundle')

! clean up work space
  call deallocate_cv(gradx)
  call deallocate_cv(grady)
  call deallocate_preds(sbias)

  end subroutine be_sv_space1_
!--------------------------------------------------------
  subroutine get_state_perts_(fc)
  use m_grid2sub1var, only: grid2sub1var
  use gridmod, only: lat1,lon1
  use gsi_bundlemod, only: gsi_bundle
  use gsi_bundlemod, only: gsi_bundlegetpointer
  implicit none
  type(gsi_bundle) :: fc
  real(r_kind),allocatable :: grdfld(:,:,:)
  real(r_kind),allocatable :: subfld(:,:,:)
  real(r_kind), pointer :: ptr3d(:,:,:)=>NULL()
  integer ii,ier
  if (mype==0) then
     allocate(grdfld(nlat,nlon,nsig))
     grdfld=zero
  else
     allocate(grdfld(0,0,0))
  endif
  allocate(subfld(lat2,lon2,nsig))
  call grid2sub1var (grdfld,subfld,ier)
  do ii=1,fc%n3d
     call gsi_bundlegetpointer(fc,trim(fc%r3(ii)%shortname),ptr3d,ier)
     ptr3d = subfld
  enddo
  deallocate(subfld)
  deallocate(grdfld)
  end subroutine get_state_perts_
!--------------------------------------------------------
  subroutine befname_ (fname,root)
  implicit none
  character(len=*),intent(in) :: fname
  integer, intent(in) :: root
  character(len=*), parameter :: myname_ = myname//"*befname"
  integer ier,clen
  if(mype==root) then
    write(6,'(3a)') myname_, ": reading B error-coeffs from ", trim(fname)
    berror_stats = trim(fname)
  endif
  clen=len(berror_stats)
  call mpi_bcast(berror_stats,clen,mpi_character,root,gsi_mpi_comm_world,ier)
  end subroutine befname_

end module m_gsibclim
