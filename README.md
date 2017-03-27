# UAFInteractiveNavigationController

Welcome to the UAFInteractiveNavigationController library. Please read this
first if you're new or need a refresher.

![Screen capture 1.](https://pengxwang.s3.amazonaws.com/files/rhymes-navigation-1.mov.gif)

More: [1](https://pengxwang.s3.amazonaws.com/files/rhymes-navigation-2.mov.gif) [2](https://pengxwang.s3.amazonaws.com/files/rhymes-navigation-3.mov.gif)

## Description

`UAFInteractiveNavigationController` mirrors `UINavigationController` behavior,
but combines it with the scroll-and-snap transition behavior of
`UIPageViewController`. It is meant for apps not using the custom
view-controller transitions iOS7.

Some requirements: it implements the interfaces found in the
[`UAFToolkit`](https://github.com/hlfcoding/UAFToolkit) library. It inherits
from the latter's boilerplate view-controller class as well, to make itself
nest-able. It also makes use of the utilities and ui-related extensions from
the latter. So, it doesn't require all of UAFToolkit, just some 'modules'. When
adding the navigation-controller and if using the
view-controller-identifier-based API, the navigation-controller must share the
same storyboard with the child-controller.

This component is a full implementation of `UAFNavigationController`, including
the paging mode. Defaults:

- `baseNavigationDirection` - `UAFNavigationDirectionHorizontal`
- `baseNavigationDuration` - `0.8f`
- `bounces` - `YES`
- `pagingEnabled` - `NO`

### Imperative (Programmatic) Navigation

The controller can perform imperative navigation operations like pushing and
popping, which are not interactive. Once started, they cannot be cancelled. The
controller can also pop to non-immediate siblings and reset its entire
child-controller stack.

### Interactive Navigation

Interactive navigation refers to being able to pan and navigate between child
view-controllers, much like `UIPageViewController`'s scroll-and-snap navigation
and `UIScrollView`'s behavior when `pagingEnabled`. Navigation follows gesture,
so it can be cancelled.

### Implementation Highlights

- `addChildViewController:animated:focused:next:`
- `popViewControllerAnimated:focused:`
- `popToViewController:animated:`
- `setViewControllers:animated:focused:`
- `cleanChildViewControllersWithNextSiblingExemption:`
- `handleRemoveChildViewController:`
- `updateChildViewControllerTilingIfNeeded`
- `handlePan:`

## Documentation

To generate these docs, just do:

```shell
cd [repo-root]
appledoc .
```
