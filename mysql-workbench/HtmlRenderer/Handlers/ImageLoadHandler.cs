// "Therefore those skilled at the unorthodox
// are infinite as heaven and earth,
// inexhaustible as the great rivers.
// When they come to an end,
// they begin again,
// like the days and months;
// they die and are reborn,
// like the four seasons."
// 
// - Sun Tsu,
// "The Art of War"

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using HtmlRenderer.Entities;
using HtmlRenderer.Utils;

namespace HtmlRenderer.Handlers
{
    /// <summary>
    /// Handler for all loading image logic.<br/>
    /// <p>
    /// Loading by <see cref="HtmlRenderer.Entities.HtmlImageLoadEventArgs"/>.<br/>
    /// Loading by file path.<br/>
    /// Loading by URI.<br/>
    /// </p>
    /// </summary>
    /// <remarks>
    /// <para>
    /// Supports sync and async image loading.
    /// </para>
    /// <para>
    /// If the image object is created by the handler on calling dispose of the handler the image will be released, this
    /// makes release of unused images faster as they can be large.<br/>
    /// Disposing image load handler will also cancel download of image from the web.
    /// </para>
    /// </remarks>
    internal sealed class ImageLoadHandler : IDisposable
    {
        #region Fields and Consts

        /// <summary>
        /// the container of the html to handle load image for
        /// </summary>
        private readonly HtmlContainer _htmlContainer;

        /// <summary>
        /// callback raised when image load process is complete with image or without
        /// </summary>
// ReSharper disable RedundantNameQualifier
        private readonly Utils.ActionInt<Image, Rectangle, bool> _loadCompleteCallback;
// ReSharper restore RedundantNameQualifier

        /// <summary>
        /// the web client used to download image from URL (to cancel on dispose)
        /// </summary>
        private WebClient _client;

        /// <summary>
        /// Must be open as long as the image is in use
        /// </summary>
        private FileStream _imageFileStream;

        /// <summary>
        /// the image instance of the loaded image
        /// </summary>
        private Image _image;

        /// <summary>
        /// the image rectangle restriction as returned from image load event
        /// </summary>
        private Rectangle _imageRectangle;

        /// <summary>
        /// to know if image load event callback was sync or async raised
        /// </summary>
        private bool _asyncCallback;

        /// <summary>
        /// flag to indicate if to release the image object on box dispose (only if image was loaded by the box)
        /// </summary>
        private bool _releaseImageObject;

        /// <summary>
        /// is the handler has been disposed
        /// </summary>
        private bool _disposed;

        #endregion


        /// <summary>
        /// Init.
        /// </summary>
        /// <param name="htmlContainer">the container of the html to handle load image for</param>
        /// <param name="loadCompleteCallback">callback raised when image load process is complete with image or without</param>
        public ImageLoadHandler(HtmlContainer htmlContainer, ActionInt<Image, Rectangle, bool> loadCompleteCallback)
        {
            ArgChecker.AssertArgNotNull(htmlContainer, "htmlContainer");
            ArgChecker.AssertArgNotNull(loadCompleteCallback, "loadCompleteCallback");

            _htmlContainer = htmlContainer;
            _loadCompleteCallback = loadCompleteCallback;
        }

        /// <summary>
        /// the image instance of the loaded image
        /// </summary>
        public Image Image
        {
            get { return _image; }
        }

        /// <summary>
        /// the image rectangle restriction as returned from image load event
        /// </summary>
        public Rectangle Rectangle
        {
            get { return _imageRectangle; }
        }

        /// <summary>
        /// Set image of this image box by analyzing the src attribute.<br/>
        /// Load the image from inline base64 encoded string.<br/>
        /// Or from calling property/method on the bridge object that returns image or URL to image.<br/>
        /// Or from file path<br/>
        /// Or from URI.
        /// </summary>
        /// <remarks>
        /// File path and URI image loading is executed async and after finishing calling <see cref="ImageLoadComplete"/>
        /// on the main thread and not thread-pool.
        /// </remarks>
        /// <param name="src">the source of the image to load</param>
        /// <param name="attributes">the collection of attributes on the element to use in event</param>
        /// <returns>the image object (null if failed)</returns>
        public void LoadImage(string src, Dictionary<string, string> attributes)
        {
            try
            {
                var args = new HtmlImageLoadEventArgs(src, attributes, OnHtmlImageLoadEventCallback);
                _htmlContainer.RaiseHtmlImageLoadEvent(args);
                _asyncCallback = !_htmlContainer.AvoidAsyncImagesLoading;

                if (!args.Handled)
                {
                    if (!string.IsNullOrEmpty(src))
                    {
                        if (src.StartsWith("data:image", StringComparison.CurrentCultureIgnoreCase))
                        {
                            SetFromInlineData(src);
                        }
                        else
                        {
                            SetImageFromPath(src);
                        }
                    }
                    else
                    {
                        ImageLoadComplete(false);
                    }
                }
            }
            catch (Exception ex)
            {
                _htmlContainer.ReportError(HtmlRenderErrorType.Image, "Exception in handling image source", ex);
                ImageLoadComplete(false);
            }
        }

        /// <summary>
        /// Performs application-defined tasks associated with freeing, releasing, or resetting unmanaged resources.
        /// </summary>
        public void Dispose()
        {
            _disposed = true;
            ReleaseObjects();
        }


        #region Private methods

        /// <summary>
        /// Set the image using callback from load image event, use the given data.
        /// </summary>
        /// <param name="path">the path to the image to load (file path or uri)</param>
        /// <param name="image">the image to load</param>
        /// <param name="imageRectangle">optional: limit to specific rectangle of the image and not all of it</param>
        private void OnHtmlImageLoadEventCallback(string path, Image image, Rectangle imageRectangle)
        {
            if (!_disposed)
            {
                _imageRectangle = imageRectangle;

                if (image != null)
                {
                    _image = image;
                    ImageLoadComplete(_asyncCallback);
                }
                else if (!string.IsNullOrEmpty(path))
                {
                    SetImageFromPath(path);
                }
                else
                {
                    ImageLoadComplete(_asyncCallback);
                }
            }
        }

        /// <summary>
        /// Load the image from inline base64 encoded string data.
        /// </summary>
        /// <param name="src">the source that has the base64 encoded image</param>
        private void SetFromInlineData(string src)
        {
            _image = GetImageFromData(src);
            if (_image == null)
                _htmlContainer.ReportError(HtmlRenderErrorType.Image, "Failed extract image from inline data");
            _releaseImageObject = true;
            ImageLoadComplete(false);
        }

        /// <summary>
        /// Extract image object from inline base64 encoded data in the src of the html img element.
        /// </summary>
        /// <param name="src">the source that has the base64 encoded image</param>
        /// <returns>image from base64 data string or null if failed</returns>
        private static Image GetImageFromData(string src)
        {
            var s = src.Substring(src.IndexOf(':') + 1).Split(new[] { ',' }, 2);
            if (s.Length == 2)
            {
                int imagePartsCount = 0, base64PartsCount = 0;
                foreach (var part in s[0].Split(new[] { ';' }))
                {
                    var pPart = part.Trim();
                    if (pPart.StartsWith("image/", StringComparison.InvariantCultureIgnoreCase))
                        imagePartsCount++;
                    if (pPart.Equals("base64", StringComparison.InvariantCultureIgnoreCase))
                        base64PartsCount++;
                }

                if (imagePartsCount > 0)
                {
                    byte[] imageData = base64PartsCount > 0 ? Convert.FromBase64String(s[1].Trim()) : new UTF8Encoding().GetBytes(Uri.UnescapeDataString(s[1].Trim()));
                    return Image.FromStream(new MemoryStream(imageData));
                }
            }
            return null;
        }

        /// <summary>
        /// Load image from path of image file or URL.
        /// </summary>
        /// <param name="path">the file path or uri to load image from</param>
        private void SetImageFromPath(string path)
        {
            var uri = CommonUtils.TryGetUri(path);
            if (uri != null && uri.Scheme != "file")
            {
                SetImageFromUrl(uri);
            }
            else
            {
                var fileInfo = CommonUtils.TryGetFileInfo(uri != null ? uri.AbsolutePath : path);
                if (fileInfo != null)
                {
                    SetImageFromFile(fileInfo);
                }
                else
                {
                    _htmlContainer.ReportError(HtmlRenderErrorType.Image, "Failed load image, invalid source: " + path);
                    ImageLoadComplete(false);
                }
            }
        }

        /// <summary>
        /// Load the image file on thread-pool thread and calling <see cref="ImageLoadComplete"/> after.
        /// </summary>
        /// <param name="source">the file path to get the image from</param>
        private void SetImageFromFile(FileInfo source)
        {
            if( source.Exists )
            {
                if (_htmlContainer.AvoidAsyncImagesLoading)
                    LoadImageFromFile(source);
                else
                    ThreadPool.QueueUserWorkItem(state => LoadImageFromFile(source));
            }
            else
            {
                ImageLoadComplete();
            }
        }

        /// <summary>
        /// Load the image file on thread-pool thread and calling <see cref="ImageLoadComplete"/> after.<br/>
        /// Calling <see cref="ImageLoadComplete"/> on the main thread and not thread-pool.
        /// </summary>
        /// <param name="source">the file path to get the image from</param>
        private void LoadImageFromFile(FileInfo source)
        {
            try
            {
                if (source.Exists)
                {
                    _imageFileStream = File.Open(source.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                    _image = Image.FromStream(_imageFileStream);
                    _releaseImageObject = true;
                }
                ImageLoadComplete();
            }
            catch (Exception ex)
            {
                _htmlContainer.ReportError(HtmlRenderErrorType.Image, "Failed to load image from disk: " + source, ex);
                ImageLoadComplete();
            }
        }

        /// <summary>
        /// Load image from the given URI by downloading it.<br/>
        /// Create local file name in temp folder from the URI, if the file already exists use it as it has already been downloaded.
        /// If not download the file using <see cref="DownloadImageFromUrlAsync"/>.
        /// </summary>
        private void SetImageFromUrl(Uri source)
        {
            var filePath = CommonUtils.GetLocalfileName(source);
            if( filePath.Exists && filePath.Length > 0 )
            {
                SetImageFromFile(filePath);
            }
            else
            {
                if (_htmlContainer.AvoidAsyncImagesLoading)
                    DownloadImageFromUrl(source, filePath);
                else
                    ThreadPool.QueueUserWorkItem(DownloadImageFromUrlAsync, new KeyValuePair<Uri, FileInfo>(source, filePath));
            }
        }

        /// <summary>
        /// Download the requested file in the URI to the given file path.<br/>
        /// Use async sockets API to download from web, <see cref="OnDownloadImageCompleted(object,System.ComponentModel.AsyncCompletedEventArgs)"/>.
        /// </summary>
        private void DownloadImageFromUrl(Uri source, FileInfo filePath)
        {
            try
            {
                using (var client = _client = new WebClient())
                {
                    client.DownloadFile(source, filePath.FullName);
                    OnDownloadImageCompleted(false, null, filePath, client);
                }
            }
            catch (Exception ex)
            {
                OnDownloadImageCompleted(false, ex, null, null);
            }
        }

        /// <summary>
        /// Download the requested file in the URI to the given file path.<br/>
        /// Use async sockets API to download from web, <see cref="OnDownloadImageCompleted(object,System.ComponentModel.AsyncCompletedEventArgs)"/>.
        /// </summary>
        /// <param name="data">key value pair of URL and file info to download the file to</param>
        private void DownloadImageFromUrlAsync(object data)
        {
            var uri = ((KeyValuePair<Uri, FileInfo>) data).Key;
            var filePath = ((KeyValuePair<Uri, FileInfo>) data).Value;

            try
            {
                _client = new WebClient();
                _client.DownloadFileCompleted += OnDownloadImageCompleted;
                _client.DownloadFileAsync(uri, filePath.FullName, filePath);
            }
            catch (Exception ex)
            {
                OnDownloadImageCompleted(false, ex, null, null);
            }
        }

        /// <summary>
        /// On download image complete to local file use <see cref="LoadImageFromFile"/> to load the image file.<br/>
        /// If the download canceled do nothing, if failed report error.
        /// </summary>
        private void OnDownloadImageCompleted(object sender, AsyncCompletedEventArgs e)
        {
            try
            {
                using (var client = (WebClient)sender)
                {
                    client.DownloadFileCompleted -= OnDownloadImageCompleted;
                    OnDownloadImageCompleted(e.Cancelled, e.Error, (FileInfo)e.UserState, client);
                }
            }
            catch (Exception ex)
            {
                OnDownloadImageCompleted(false, ex, null, null);
            }
        }

        /// <summary>
        /// On download image complete to local file use <see cref="LoadImageFromFile"/> to load the image file.<br/>
        /// If the download canceled do nothing, if failed report error.
        /// </summary>
        private void OnDownloadImageCompleted(bool cancelled, Exception error, FileInfo filePath, WebClient client)
        {
            if (!cancelled && !_disposed)
            {
                if (error == null)
                {
                    filePath.Refresh();
                    var contentType = CommonUtils.GetResponseContentType(client);
                    if( contentType != null && contentType.StartsWith("image", StringComparison.OrdinalIgnoreCase) )
                    {
                        LoadImageFromFile(filePath);
                    }
                    else
                    {
                        _htmlContainer.ReportError(HtmlRenderErrorType.Image, "Failed to load image, not image content type: " + contentType);
                        ImageLoadComplete();
                        filePath.Delete();
                    }
                }
                else
                {
                    _htmlContainer.ReportError(HtmlRenderErrorType.Image, "Failed to load image from URL: " + client.BaseAddress, error);
                    ImageLoadComplete();
                }
            }
        }

        /// <summary>
        /// Flag image load complete and request refresh for re-layout and invalidate.
        /// </summary>
        private void ImageLoadComplete(bool async = true)
        {
            // can happen if some operation return after the handler was disposed
            if(_disposed)
                ReleaseObjects();
            else 
                _loadCompleteCallback(_image, _imageRectangle, async);
        }

        /// <summary>
        /// Release the image and client objects.
        /// </summary>
        private void ReleaseObjects()
        {
            if (_releaseImageObject && _image != null)
            {
                _image.Dispose();
                _image = null;
            }
            if (_imageFileStream != null)
            {
                _imageFileStream.Dispose();
                _imageFileStream = null;
            }
            if (_client != null)
            {
                _client.CancelAsync();
                _client.Dispose();
                _client = null;
            }
        }

        #endregion
    }
}
